require "rails_helper"

RSpec.describe "Passwordless accounts", type: :request do
  include_context "with google oauth"

  let(:user) { create(:user, :passwordless) }

  before { user.identities.first.update!(provider_uid: "google-sub-1") }

  it "exposes password_set in the user's own profile" do
    get "/api/v1/me", headers: auth_headers(user)
    expect(json["data"]["password_set"]).to be(false)

    get "/api/v1/me", headers: auth_headers(create(:user))
    expect(json["data"]["password_set"]).to be(true)
  end

  it "answers a password login attempt like any wrong credentials" do
    login(user.email, "Senha@123")

    expect(response).to have_http_status(:unauthorized)
    expect(json["error"]["code"]).to eq("invalid_credentials")
  end

  it "lets the owner start a password reset and set the first password" do
    post "/api/v1/auth/password/forgot", params: { email: user.email }, as: :json
    expect(response).to have_http_status(:accepted)

    post "/api/v1/auth/password/reset",
      params: { token: user.generate_token_for(:password_reset), password: "Nova@12345", password_confirmation: "Nova@12345" }, as: :json
    expect(response).to have_http_status(:ok)
    expect(user.reload.authenticate("Nova@12345")).to be_truthy
  end

  context "with 2FA enabled" do
    let(:user) { create(:user, :passwordless, :with_2fa) }

    it "sets the first password re-authenticating with the 2FA code" do
      patch "/api/v1/me/password", params: { code: otp_code(user), password: "Nova@12345", password_confirmation: "Nova@12345" },
        headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload).to be_password_set
    end

    it "deletes the account verifying the 2FA code only once" do
      delete "/api/v1/me", params: { code: otp_code(user) }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:no_content)
      expect(user.reload).to be_anonymized
    end
  end

  context "without 2FA" do
    it "cannot re-authenticate sensitive actions yet" do
      patch "/api/v1/me/password", params: { password: "Nova@12345", password_confirmation: "Nova@12345" }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json["error"]["code"]).to eq("reauthentication_unavailable")
      expect(user.reload).not_to be_password_set
    end
  end

  it "includes the identities in the data export without the provider uid" do
    get "/api/v1/me/export", headers: auth_headers(user)

    identities = json["content"]["identities"]
    expect(identities.size).to eq(1)
    expect(identities.first).to include("provider" => "google")
    expect(identities.first.keys).not_to include("provider_uid")
  end

  describe "re-authenticating with a provider token" do
    def set_password(params)
      patch "/api/v1/me/password", params: { password: "Nova@12345", password_confirmation: "Nova@12345" }.merge(params), headers: auth_headers(user), as: :json
    end

    it "accepts a fresh token of a linked account" do
      set_password(id_token: google_id_token)

      expect(response).to have_http_status(:ok)
      expect(user.reload).to be_password_set
    end

    it "accepts an explicit provider" do
      set_password(id_token: google_id_token, provider: "google")
      expect(response).to have_http_status(:ok)
    end

    it "rejects a valid token of an account that is not linked to the user" do
      set_password(id_token: google_id_token(sub: "someone-else"))

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_provider_token")
      expect(user.reload).not_to be_password_set
    end

    it "rejects an invalid token and a provider that is not supported" do
      set_password(id_token: "garbage")
      expect(json.dig("error", "code")).to eq("invalid_provider_token")

      set_password(id_token: google_id_token, provider: "myspace")
      expect(json.dig("error", "code")).to eq("invalid_provider_token")
    end

    context "with an Apple identity" do
      include_context "with apple oauth"

      before { user.identities.first.update!(provider: :apple, provider_uid: "apple-sub-1") }

      it "accepts a fresh Apple token" do
        set_password(provider: "apple", id_token: apple_id_token)

        expect(response).to have_http_status(:ok)
        expect(user.reload).to be_password_set
      end

      it "rejects a Google token presented as Apple" do
        set_password(provider: "apple", id_token: google_id_token)
        expect(json.dig("error", "code")).to eq("invalid_provider_token")
      end
    end

    it "asks to retry when Google's keys cannot be fetched" do
      stub_request(:get, GoogleOauthHelpers::GOOGLE_JWKS_URL).to_return(status: 500)

      set_password(id_token: google_id_token)

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("provider_unavailable")
    end

    it "lets the token replace the 2FA code on actions that only re-authenticate" do
      user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
      create(:identity, user: user, provider: :apple)

      delete "/api/v1/me/identities/#{user.identities.find_by(provider: :apple).id}", params: { id_token: google_id_token }, headers: auth_headers(user), as: :json

      expect(response).to have_http_status(:no_content)
    end

    it "still asks for the 2FA code on account deletion" do
      user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)

      delete "/api/v1/me", params: { id_token: google_id_token }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_two_factor_code")

      delete "/api/v1/me", params: { id_token: google_id_token, code: otp_code(user) }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:no_content)
    end
  end
end
