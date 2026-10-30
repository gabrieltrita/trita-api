require "rails_helper"

RSpec.describe "Auth::Oauth", type: :request do
  include_context "with google oauth"

  let(:consents) { { accept_terms: true, accept_privacy: true } }

  def google_login(token = google_id_token, extra: {}, headers: {})
    post "/api/v1/auth/oauth/google", params: { id_token: token }.merge(extra), headers: headers, as: :json
  end

  describe "POST /api/v1/auth/oauth/google" do
    context "with a known Google account" do
      let!(:identity) { create(:identity, provider: :google, provider_uid: "google-sub-1", user: create(:user, email: "other@example.com")) }

      it "logs in and audits the provider" do
        expect { google_login }.not_to change { [ User.count, Identity.count ] }

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "user", "id")).to eq(identity.user_id)
        expect(json.dig("data", "tokens", "access_token")).to be_present
        log = AuditLog.find_by(action: "auth.login", target_id: identity.user_id)
        expect(log.metadata).to eq("two_factor" => false, "provider" => "google")
      end

      it "answers with the refresh cookie in cookie mode" do
        google_login(headers: { "X-Token-Transport" => "cookie" })

        expect(json.dig("data", "tokens", "refresh_token_transport")).to eq("cookie")
        expect(response.headers["Set-Cookie"]).to include("#{Rails.configuration.x.app.slug}_refresh=")
      end

      it "returns the 2FA challenge when the account has 2FA" do
        identity.user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)

        google_login

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "two_factor_required")).to be(true)
        expect(json.dig("data", "tokens")).to be_nil

        post "/api/v1/auth/two_factor", params: { challenge_token: json.dig("data", "challenge_token"), code: otp_code(identity.user) }, as: :json
        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "tokens", "access_token")).to be_present
      end
    end

    context "with the same email as a confirmed account" do
      let!(:user) { create(:user, email: "person@example.com") }

      it "links the identity, audits it and warns the owner" do
        expect { google_login }.to have_enqueued_mail(UserMailer, :identity_linked)

        expect(response).to have_http_status(:ok)
        expect(json.dig("data", "user", "id")).to eq(user.id)
        expect(user.identities.pluck(:provider)).to eq([ "google" ])
        expect(user.reload.authenticate("Senha@123")).to be_truthy
        log = AuditLog.find_by(action: "identity.linked", target_id: user.id)
        expect(log.metadata).to eq("provider" => "google", "reclaimed" => false)
      end

      it "still asks for the 2FA code" do
        user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)

        google_login

        expect(json.dig("data", "two_factor_required")).to be(true)
        expect(user.identities.count).to eq(1)
      end

      it "refuses a second Google account for the same user" do
        create(:identity, user: user, provider: :google, provider_uid: "another-google-sub")

        google_login

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_failed")
      end
    end

    context "with the same email as an unconfirmed account" do
      let!(:user) { create(:user, :unconfirmed, email: "person@example.com") }

      it "discards the password and the sessions, confirms the email and links the identity" do
        stale = tokens_for(user)

        expect { google_login }.to have_enqueued_mail(UserMailer, :identity_linked)

        expect(response).to have_http_status(:ok)
        user.reload
        expect(user).to be_confirmed
        expect(user).not_to be_password_set
        expect(user.identities.count).to eq(1)
        expect(AuditLog.find_by(action: "identity.linked", target_id: user.id).metadata).to include("reclaimed" => true)

        post "/api/v1/auth/refresh", params: { refresh_token: stale[:refresh_token] }, as: :json
        expect(response).to have_http_status(:unauthorized)
        login("person@example.com", "Senha@123")
        expect(json.dig("error", "code")).to eq("invalid_credentials")
      end
    end

    context "with an email that has no account" do
      it "creates a confirmed account without a password and records the consents" do
        expect { google_login(extra: consents.merge(accept_marketing: true)) }.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        user = User.find_by(email: "person@example.com")
        expect(user).to be_confirmed
        expect(user).not_to be_password_set
        expect(user).to have_attributes(first_name: "Person", last_name: "Example")
        expect(user.identities.first).to have_attributes(provider: "google", email_at_link: "person@example.com")
        expect(Consent.status_for(user).transform_values { |v| v[:granted] }).to eq("terms" => true, "privacy" => true, "marketing" => true)
        expect(AuditLog.find_by(action: "user.registered", target_id: user.id).metadata).to eq("provider" => "google")
        expect(json.dig("data", "user", "id")).to eq(user.id)
      end

      it "does not grant marketing unless asked" do
        google_login(extra: consents)

        user = User.find_by(email: "person@example.com")
        expect(Consent.status_for(user)["marketing"][:granted]).to be(false)
      end

      it "requires the terms and privacy consents" do
        expect { google_login }.not_to change(User, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("validation_failed")
        expect(json.dig("error", "details").keys).to contain_exactly("accept_terms", "accept_privacy")
        expect(json.dig("error", "details", "accept_terms", 0, "code")).to eq("required")
      end

      it "falls back to the email name and trims long names" do
        google_login(google_id_token(given_name: nil, family_name: "x" * 150), extra: consents)

        user = User.find_by(email: "person@example.com")
        expect(user.first_name).to eq("person")
        expect(user.last_name.length).to eq(100)
      end

      it "keeps the name from the token over the one the client sends" do
        google_login(extra: consents.merge(first_name: "Impostor", last_name: "Other"))

        expect(User.find_by(email: "person@example.com")).to have_attributes(first_name: "Person", last_name: "Example")
      end

      it "accepts a Google profile without a family name" do
        google_login(google_id_token(family_name: nil), extra: consents)

        expect(User.find_by(email: "person@example.com").last_name).to be_nil
      end

      it "survives two simultaneous requests creating the same account" do
        calls = 0
        allow_any_instance_of(Auth::OauthSignin).to receive(:attempt).and_wrap_original do |original|
          calls += 1
          raise ActiveRecord::RecordNotUnique if calls == 1

          original.call
        end

        expect { google_login(extra: consents) }.to change(User, :count).by(1)
        expect(response).to have_http_status(:ok)
      end
    end

    context "with a bad request" do
      it "rejects an invalid token" do
        google_login("garbage")

        expect(response).to have_http_status(:unauthorized)
        expect(json.dig("error", "code")).to eq("oauth_token_invalid")
      end

      it "rejects an unverified email" do
        google_login(google_id_token(email_verified: false), extra: consents)

        expect(response).to have_http_status(:unauthorized)
        expect(json.dig("error", "code")).to eq("oauth_email_unverified")
        expect(User.find_by(email: "person@example.com")).to be_nil
      end

      it "requires the id_token" do
        post "/api/v1/auth/oauth/google", params: {}, as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it "answers 503 when Google's keys cannot be fetched" do
        stub_request(:get, GoogleOauthHelpers::GOOGLE_JWKS_URL).to_return(status: 500)

        google_login

        expect(response).to have_http_status(:service_unavailable)
        expect(json.dig("error", "code")).to eq("oauth_provider_unavailable")
      end
    end
  end
end
