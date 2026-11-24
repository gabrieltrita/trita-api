require "rails_helper"

RSpec.describe "Me::TwoFactor", type: :request do
  let(:user) { create(:user, password: "Senha@123") }

  it "shows the 2FA status" do
    get "/api/v1/me/two_factor", headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    expect(json["data"]).to eq("enabled" => false, "required" => false, "backup_codes_remaining" => 0)
  end

  context "without 2FA enabled" do
    it "cannot disable it" do
      delete "/api/v1/me/two_factor", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("two_factor_not_enabled")
    end

    it "cannot regenerate backup codes" do
      post "/api/v1/me/two_factor/backup_codes", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("two_factor_not_enabled")
    end
  end

  it "enables 2FA in two steps and ends the other sessions" do
    current = tokens_for(user)
    other = tokens_for(user)
    headers = bearer(current[:access_token])

    post "/api/v1/me/two_factor/setup", params: { current_password: "Senha@123" }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "provisioning_uri")).to start_with("otpauth://totp/#{ERB::Util.url_encode(Rails.configuration.x.app.name)}")

    post "/api/v1/me/two_factor/enable", params: { code: "000000" }, headers: headers, as: :json
    expect(response).to have_http_status(:unprocessable_content)

    post "/api/v1/me/two_factor/enable", params: { code: otp_code(user) }, headers: headers, as: :json
    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "backup_codes").size).to eq(10)
    expect(user.reload).to be_two_factor_enabled

    get "/api/v1/me", headers: bearer(other[:access_token])
    expect(response).to have_http_status(:unauthorized)
    get "/api/v1/me", headers: headers
    expect(response).to have_http_status(:ok)
  end

  it "requires the current password on setup" do
    post "/api/v1/me/two_factor/setup", params: { current_password: "Errada@123" }, headers: auth_headers(user), as: :json
    expect(response).to have_http_status(:unprocessable_content)
  end

  context "with 2FA enabled" do
    let(:user) { create(:user, :with_2fa, password: "Senha@123") }

    it "does not restart the setup and keeps the current secret" do
      secret = user.otp_secret
      post "/api/v1/me/two_factor/setup", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("two_factor_already_enabled")
      expect(user.reload.otp_secret).to eq(secret)
    end

    it "disables with password and code and emails the user" do
      expect {
        delete "/api/v1/me/two_factor", params: { current_password: "Senha@123", code: otp_code(user) }, headers: auth_headers(user), as: :json
      }.to have_enqueued_mail(UserMailer, :two_factor_disabled)
      expect(response).to have_http_status(:no_content)
      expect(user.reload).not_to be_two_factor_enabled
    end

    it "does not disable without the code" do
      delete "/api/v1/me/two_factor", params: { current_password: "Senha@123" }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload).to be_two_factor_enabled
    end

    it "generates new backup codes" do
      post "/api/v1/me/two_factor/backup_codes", params: { current_password: "Senha@123", code: otp_code(user) }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "backup_codes").size).to eq(10)
    end
  end

  it "does not let admins disable 2FA" do
    admin = create(:user, :admin, password: "Senha@123")
    delete "/api/v1/me/two_factor", params: { current_password: "Senha@123", code: otp_code(admin) }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:forbidden)
    expect(admin.reload).to be_two_factor_enabled
  end

  it "flags that an admin without 2FA must set it up on login" do
    create(:user, :admin_without_2fa, email: "chefe@example.com", password: "Senha@123")
    login("chefe@example.com", "Senha@123")
    expect(json.dig("data", "two_factor_setup_required")).to be(true)
  end
end
