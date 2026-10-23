require "rails_helper"

RSpec.describe "Me", type: :request do
  let(:user) { create(:user, email: "eu@example.com", password: "Senha@123") }

  describe "GET /api/v1/me" do
    it "returns the profile without internal fields" do
      get "/api/v1/me", headers: auth_headers(user)
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "email")).to eq("eu@example.com")
      expect(json["data"]).to include("email_confirmed" => true, "two_factor_enabled" => false, "pending_email" => nil)
      expect(json["data"].keys).not_to include("password_digest", "otp_secret", "otp_backup_code_digests")
    end

    it "rejects a valid token whose user no longer exists" do
      token = Auth::JsonWebToken.encode({ sub: SecureRandom.uuid, sid: SecureRandom.uuid, type: "access" }, expires_at: 15.minutes.from_now)
      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_token")
    end

    it "expires tokens issued before the password changed, even without a revocation" do
      headers = auth_headers(user)
      travel(1.second) { user.update_columns(password_changed_at: Time.current) }

      travel(2.seconds) do
        get "/api/v1/me", headers: headers
        expect(response).to have_http_status(:unauthorized)
        expect(json.dig("error", "code")).to eq("session_expired")
      end
    end

    it "identifies the user to Sentry by id only when Sentry is enabled" do
      with_sentry do
        allow(Sentry).to receive(:set_user).and_call_original

        get "/api/v1/me", headers: auth_headers(user)
        expect(response).to have_http_status(:ok)
        expect(Sentry).to have_received(:set_user).with(id: user.id)
      end
    end
  end

  describe "PATCH /api/v1/me" do
    it "updates the profile but ignores role and email" do
      patch "/api/v1/me", params: { first_name: "New", role: "admin", email: "outro@example.com" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      user.reload
      expect(user.first_name).to eq("New")
      expect(user).to be_user
      expect(user.email).to eq("eu@example.com")
    end

    it "returns per-field errors for an invalid profile" do
      patch "/api/v1/me", params: { first_name: "" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details", "first_name", 0, "code")).to eq("blank")
    end
  end

  describe "PATCH /api/v1/me/password" do
    it "requires the current password" do
      patch "/api/v1/me/password", params: { current_password: "Errada@123", password: "Nova@1234" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("invalid_current_password")
    end

    it "rejects a weak new password and keeps the old one" do
      patch "/api/v1/me/password", params: { current_password: "Senha@123", password: "weak", password_confirmation: "weak" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details", "password").map { |e| e["code"] }).to include("too_short")
      expect(user.reload.authenticate("Senha@123")).to be_truthy
    end

    it "changes the password, invalidates every old token and returns a new session" do
      old = tokens_for(user)
      other_device = tokens_for(user)
      travel 1.second

      patch "/api/v1/me/password",
        params: { current_password: "Senha@123", password: "Nova@1234", password_confirmation: "Nova@1234" },
        headers: bearer(old[:access_token]), as: :json
      expect(response).to have_http_status(:ok)
      new_access = json.dig("data", "tokens", "access_token")

      get "/api/v1/me", headers: bearer(old[:access_token])
      expect(response).to have_http_status(:unauthorized)

      post "/api/v1/auth/refresh", params: { refresh_token: other_device[:refresh_token] }, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/me", headers: bearer(new_access)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "email change" do
    it "requires the current password" do
      patch "/api/v1/me/email", params: { email: "novo@example.com", current_password: "Errada@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.unconfirmed_email).to be_nil
    end

    it "only changes after the new address is confirmed and notifies the old one" do
      expect {
        patch "/api/v1/me/email", params: { email: "Novo@Example.com", current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      }.to have_enqueued_mail(UserMailer, :email_change_confirmation).with(user)
        .and have_enqueued_mail(UserMailer, :email_change_requested).with(user)

      expect(response).to have_http_status(:accepted)
      expect(user.reload.email).to eq("eu@example.com")
      expect(user.unconfirmed_email).to eq("novo@example.com")

      token = user.generate_token_for(:email_change)
      post "/api/v1/auth/email/confirm", params: { token: token }, as: :json
      expect(response).to have_http_status(:ok)
      expect(user.reload.email).to eq("novo@example.com")
      expect(user.unconfirmed_email).to be_nil
      expect(AuditLog.where(action: "user.email_changed", target_id: user.id)).to exist

      post "/api/v1/auth/email/confirm", params: { token: token }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "does not reveal whether the new email belongs to another account" do
      create(:user, email: "ocupado@example.com")

      expect {
        patch "/api/v1/me/email", params: { email: "ocupado@example.com", current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      }.not_to have_enqueued_mail(UserMailer, :email_change_confirmation)
      expect(response).to have_http_status(:accepted)
    end

    it "rejects an invalid email" do
      patch "/api/v1/me/email", params: { email: "nao-e-email", current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "rejects the current email as the new one" do
      patch "/api/v1/me/email", params: { email: "eu@example.com", current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details", "email", 0, "code")).to eq("same_as_current")
    end
  end

  describe "DELETE /api/v1/me" do
    it "requires the current password" do
      delete "/api/v1/me", params: { current_password: "Errada@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload).not_to be_anonymized
    end

    it "requires the 2FA code when enabled" do
      user.update!(otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
      delete "/api/v1/me", params: { current_password: "Senha@123", code: "000000" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)

      delete "/api/v1/me", params: { current_password: "Senha@123", code: otp_code(user) }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:no_content)
    end

    it "anonymizes the account and ends the session" do
      headers = auth_headers(user)
      delete "/api/v1/me", params: { current_password: "Senha@123" }, headers: headers, as: :json

      expect(response).to have_http_status(:no_content)
      expect(user.reload).to be_anonymized
      get "/api/v1/me", headers: headers
      expect(response).to have_http_status(:unauthorized)

      login("eu@example.com", "Senha@123")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  it "lists the roles" do
    get "/api/v1/roles", headers: auth_headers(user)
    expect(json["data"].map { |r| r["name"] }).to eq(%w[user admin])
  end
end
