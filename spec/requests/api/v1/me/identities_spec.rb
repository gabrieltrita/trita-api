require "rails_helper"

RSpec.describe "Me::Identities", type: :request do
  include_context "with google oauth"

  let(:user) { create(:user) }

  describe "GET /api/v1/me/identities" do
    it "lists the linked identities without the provider uid" do
      create(:identity, user: user, provider: :google, email_at_link: "me@gmail.com")
      create(:identity, provider: :apple)

      get "/api/v1/me/identities", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(json["data"].size).to eq(1)
      expect(json["data"].first).to include("provider" => "google", "email_at_link" => "me@gmail.com")
      expect(json["data"].first.keys).not_to include("provider_uid")
    end

    it "requires authentication" do
      get "/api/v1/me/identities"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/me/identities/:id" do
    let!(:identity) { create(:identity, user: user) }

    it "unlinks the identity after the password check and audits it" do
      delete "/api/v1/me/identities/#{identity.id}", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:no_content)
      expect(Identity.exists?(identity.id)).to be(false)
      log = AuditLog.find_by(action: "identity.unlinked", target_id: user.id)
      expect(log.metadata).to eq("provider" => "google")
    end

    it "keeps the identity when the password is wrong" do
      delete "/api/v1/me/identities/#{identity.id}", params: { current_password: "Errada@123" }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("invalid_current_password")
      expect(Identity.exists?(identity.id)).to be(true)
    end

    it "does not touch another user's identity" do
      stranger = create(:identity)

      delete "/api/v1/me/identities/#{stranger.id}", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:not_found)
      expect(Identity.exists?(stranger.id)).to be(true)
    end

    context "without a password" do
      let(:user) { create(:user, :passwordless, :with_2fa) }
      let(:identity) { user.identities.first }

      it "refuses to remove the only way to log in" do
        delete "/api/v1/me/identities/#{identity.id}", params: { code: otp_code(user) }, headers: auth_headers(user), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]["code"]).to eq("last_login_method")
        expect(Identity.exists?(identity.id)).to be(true)
      end

      it "unlinks one identity while another remains, re-authenticating with the 2FA code" do
        create(:identity, user: user, provider: :apple)

        delete "/api/v1/me/identities/#{identity.id}", params: { code: otp_code(user) }, headers: auth_headers(user), as: :json

        expect(response).to have_http_status(:no_content)
        expect(user.identities.reload.map(&:provider)).to eq([ "apple" ])
      end

      it "rejects a wrong 2FA code" do
        create(:identity, user: user, provider: :apple)

        delete "/api/v1/me/identities/#{identity.id}", params: { code: "000000" }, headers: auth_headers(user), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]["code"]).to eq("invalid_two_factor_code")
      end
    end

    context "without a password and without 2FA" do
      let(:user) { create(:user, :passwordless) }
      let(:identity) { user.identities.first }

      it "cannot re-authenticate yet" do
        create(:identity, user: user, provider: :apple)

        delete "/api/v1/me/identities/#{identity.id}", headers: auth_headers(user), as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json["error"]["code"]).to eq("reauthentication_unavailable")
      end
    end
  end

  describe "POST /api/v1/me/identities" do
    let(:token) { google_id_token(sub: "work-sub", email: "work@gmail.com") }

    def link(headers: auth_headers(user), **params)
      post "/api/v1/me/identities", params: { id_token: token }.merge(params), headers: headers, as: :json
    end

    it "links a provider account whose email differs from the user's, audits it and warns the owner" do
      expect { link(current_password: "Senha@123") }.to have_enqueued_mail(UserMailer, :identity_linked)

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("provider" => "google", "email_at_link" => "work@gmail.com")
      expect(user.identities.first).to have_attributes(provider: "google", provider_uid: "work-sub")
      expect(AuditLog.find_by(action: "identity.linked", target_id: user.id).metadata).to eq("provider" => "google")
    end

    it "accepts an explicit provider" do
      link(provider: "google", current_password: "Senha@123")
      expect(response).to have_http_status(:created)
    end

    context "with an Apple token" do
      include_context "with apple oauth"

      it "links the Apple account" do
        link(provider: "apple", id_token: apple_id_token(sub: "apple-new", email: "relay@privaterelay.appleid.com"), current_password: "Senha@123")

        expect(response).to have_http_status(:created)
        expect(json["data"]).to include("provider" => "apple", "email_at_link" => "relay@privaterelay.appleid.com")
      end
    end

    it "keeps the account unlinked when the password is wrong" do
      link(current_password: "Errada@123")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_current_password")
      expect(user.identities).to be_empty
    end

    it "rejects a provider that is not supported" do
      link(provider: "myspace", current_password: "Senha@123")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details", "provider", 0, "code")).to eq("inclusion")
    end

    it "rejects a provider account that belongs to another user" do
      create(:identity, provider: :google, provider_uid: "work-sub")

      link(current_password: "Senha@123")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("identity_already_linked")
    end

    it "rejects the same provider account twice and a second account of the same provider" do
      link(current_password: "Senha@123")
      link(current_password: "Senha@123")
      expect(json.dig("error", "code")).to eq("identity_already_linked")

      post "/api/v1/me/identities", params: { id_token: google_id_token(sub: "other-sub"), current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(json.dig("error", "code")).to eq("identity_already_linked")
      expect(user.identities.count).to eq(1)
    end

    it "answers identity_already_linked when a simultaneous request wins the race" do
      allow_any_instance_of(Identity).to receive(:save!).and_raise(ActiveRecord::RecordNotUnique)

      link(current_password: "Senha@123")

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("identity_already_linked")
    end

    it "rejects an invalid provider token" do
      link(id_token: "garbage", current_password: "Senha@123")

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("oauth_token_invalid")
    end

    it "requires the id_token" do
      post "/api/v1/me/identities", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "answers 503 when Google's keys cannot be fetched" do
      stub_request(:get, GoogleOauthHelpers::GOOGLE_JWKS_URL).to_return(status: 500)

      link(current_password: "Senha@123")

      expect(response).to have_http_status(:service_unavailable)
      expect(json.dig("error", "code")).to eq("oauth_provider_unavailable")
    end

    it "requires authentication" do
      link(headers: {})
      expect(response).to have_http_status(:unauthorized)
    end

    context "without a password" do
      let(:user) { create(:user, :passwordless, :with_2fa) }

      before { user.identities.first.update!(provider: :apple) }

      it "re-authenticates with the 2FA code" do
        link(code: otp_code(user))

        expect(response).to have_http_status(:created)
        expect(user.identities.pluck(:provider)).to contain_exactly("apple", "google")
      end

      it "does not accept the provider token being linked as re-authentication" do
        link

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("invalid_two_factor_code")
      end
    end

    context "without a password and without 2FA" do
      let(:user) { create(:user, :passwordless) }

      it "cannot link even when sending a provider token" do
        link

        expect(response).to have_http_status(:unprocessable_content)
        expect(json.dig("error", "code")).to eq("reauthentication_unavailable")
      end
    end
  end
end
