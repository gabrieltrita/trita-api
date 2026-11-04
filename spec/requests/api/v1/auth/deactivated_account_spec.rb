require "rails_helper"

RSpec.describe "Deactivated accounts", type: :request do
  let(:user) { create(:user, email: "suspended@example.com") }

  def expect_invalid_credentials
    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("invalid_credentials")
  end

  it "answers login like a wrong password without counting a failed attempt" do
    user.deactivate!

    login("suspended@example.com", "Senha@123")

    expect_invalid_credentials
    expect(user.reload.failed_login_attempts).to eq(0)
    expect(AuditLog.where(action: "auth.login_blocked", target_id: user.id)).to exist
  end

  it "refuses the 2FA step of a challenge issued before the deactivation" do
    user = create(:user, :with_2fa)
    login(user.email, "Senha@123")
    challenge = json.dig("data", "challenge_token")
    user.deactivate!

    post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: otp_code(user) }, as: :json

    expect_invalid_credentials
  end

  it "refuses the confirmation link of a deactivated account" do
    user = create(:user, :unconfirmed)
    token = user.generate_token_for(:email_confirmation)
    user.deactivate!

    post "/api/v1/auth/confirm", params: { token: token }, as: :json

    expect_invalid_credentials
  end

  it "refuses refresh tokens and access tokens issued before the deactivation" do
    tokens = tokens_for(user)
    user.update_column(:deactivated_at, Time.current)

    post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/me", headers: auth_headers(user, tokens: tokens)
    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("invalid_token")
  end

  context "with social login" do
    include_context "with google oauth"

    it "answers like a wrong password" do
      create(:identity, provider: :google, provider_uid: "google-sub-1", user: user)
      user.deactivate!

      post "/api/v1/auth/oauth/google", params: { id_token: google_id_token }, as: :json

      expect_invalid_credentials
    end
  end
end
