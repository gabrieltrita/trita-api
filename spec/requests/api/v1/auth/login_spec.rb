require "rails_helper"

RSpec.describe "Login, lockout and 2FA", type: :request do
  let(:password) { "Senha@123" }
  let!(:user) { create(:user, email: "login@example.com", password: password) }

  describe "POST /api/v1/auth/login" do
    it "authenticates with valid credentials" do
      login("LOGIN@example.com", password)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "tokens", "token_type")).to eq("Bearer")
      expect(user.reload.sign_in_count).to eq(1)
      expect(AuditLog.where(action: "auth.login", target_id: user.id)).to exist
    end

    it "answers a wrong password and an unknown email identically" do
      login("login@example.com", "Errada@123")
      wrong_password = [ response.status, json ]
      login("nao@existe.com", password)

      expect([ response.status, json ]).to eq(wrong_password)
      expect(response).to have_http_status(:unauthorized)
    end

    it "requires a confirmed email (only after the right password)" do
      create(:user, :unconfirmed, email: "pendente@example.com", password: password)

      login("pendente@example.com", "Errada@123")
      expect(response).to have_http_status(:unauthorized)

      login("pendente@example.com", password)
      expect(response).to have_http_status(:forbidden)
      expect(json.dig("error", "code")).to eq("email_not_confirmed")
    end

    it "stores the device user agent on the new session" do
      login("login@example.com", password, headers: { "User-Agent" => "TritaTest/1.0" })

      expect(response).to have_http_status(:ok)
      expect(user.refresh_tokens.last.user_agent).to eq("TritaTest/1.0")
    end
  end

  describe "progressive lockout" do
    it "locks after 5 failures, rejecting even the right password with the same message" do
      5.times { login("login@example.com", "Errada@123") }
      expect(user.reload).to be_access_locked

      login("login@example.com", password)
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_credentials")

      travel 16.minutes do
        login("login@example.com", password)
        expect(response).to have_http_status(:ok)
        expect(user.reload.failed_login_attempts).to eq(0)
      end
    end
  end

  describe "2FA" do
    let!(:user) { create(:user, :with_2fa, email: "dois@example.com", password: password) }

    it "asks for the second factor and only issues tokens with a valid code" do
      login("dois@example.com", password)
      expect(json.dig("data", "two_factor_required")).to be(true)
      expect(json.dig("data", "tokens")).to be_nil
      challenge = json.dig("data", "challenge_token")

      post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: "000000" }, as: :json
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: otp_code(user) }, as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "tokens", "access_token")).to be_present

      travel 31.seconds do
        post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: otp_code(user) }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    it "does not accept the challenge_token as an access token" do
      login("dois@example.com", password)
      get "/api/v1/me", headers: bearer(json.dig("data", "challenge_token"))
      expect(response).to have_http_status(:unauthorized)
    end

    it "counts wrong codes towards the lockout" do
      login("dois@example.com", password)
      challenge = json.dig("data", "challenge_token")
      5.times { post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: "123456" }, as: :json }

      expect(user.reload).to be_access_locked
    end

    it "accepts a backup code" do
      codes = user.regenerate_backup_codes!
      login("dois@example.com", password)
      post "/api/v1/auth/two_factor", params: { challenge_token: json.dig("data", "challenge_token"), code: codes.first }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "rejects a pending challenge once the account gets locked" do
      login("dois@example.com", password)
      challenge = json.dig("data", "challenge_token")
      5.times { user.register_failed_login! }

      post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: otp_code(user) }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_token")
    end

    it "rejects a pending challenge once the account is deleted" do
      login("dois@example.com", password)
      challenge = json.dig("data", "challenge_token")
      user.anonymize!

      post "/api/v1/auth/two_factor", params: { challenge_token: challenge, code: "123456" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_token")
    end
  end
end
