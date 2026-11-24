require "rails_helper"

RSpec.describe "Tokens, sessions and logout", type: :request do
  let(:user) { create(:user) }

  describe "protected routes" do
    it "requires a token" do
      get "/api/v1/me"
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("missing_token")
    end

    it "rejects an invalid token" do
      get "/api/v1/me", headers: bearer("abc.def.ghi")
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a refresh token used as an access token" do
      get "/api/v1/me", headers: bearer(tokens_for(user)[:refresh_token])
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an expired token" do
      headers = auth_headers(user)
      travel 16.minutes do
        get "/api/v1/me", headers: headers
        expect(response).to have_http_status(:unauthorized)
        expect(json.dig("error", "code")).to eq("invalid_token")
      end
    end

    it "rejects an unsigned token (alg none)" do
      claims = { sub: user.id, sid: SecureRandom.uuid, type: "access", iss: Auth::JsonWebToken::ISSUER, exp: 1.hour.from_now.to_i, iat: Time.current.to_i, jti: SecureRandom.uuid }
      unsigned = JWT.encode(claims, nil, "none")

      get "/api/v1/me", headers: bearer(unsigned)
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_token")
    end

    it "rejects a token signed with another secret" do
      forged = JWT.encode({ sub: user.id, type: "access", iss: Auth::JsonWebToken::ISSUER, exp: 1.hour.from_now.to_i, iat: Time.current.to_i, jti: "x" }, "another-secret", "HS256")
      get "/api/v1/me", headers: bearer(forged)
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_token")
    end

    it "accepts tokens signed with the previous secret during rotation (JWT_SECRET_PREVIOUS)" do
      old_secret = ENV.fetch("JWT_SECRET")
      token = tokens_for(user)[:access_token]

      begin
        ENV["JWT_SECRET_PREVIOUS"] = old_secret
        ENV["JWT_SECRET"] = SecureRandom.hex(64)
        get "/api/v1/me", headers: bearer(token)
        expect(response).to have_http_status(:ok)
      ensure
        ENV["JWT_SECRET"] = old_secret
        ENV.delete("JWT_SECRET_PREVIOUS")
      end
    end
  end

  describe "POST /api/v1/auth/refresh" do
    it "rotates the refresh token within the same session" do
      old = tokens_for(user)[:refresh_token]
      family = RefreshToken.find_by_raw_token(old).family_id

      post "/api/v1/auth/refresh", params: { refresh_token: old }, as: :json
      expect(response).to have_http_status(:ok)
      new_token = json.dig("data", "tokens", "refresh_token")
      expect(new_token).not_to eq(old)
      expect(RefreshToken.find_by_raw_token(new_token).family_id).to eq(family)
    end

    it "detects reuse and revokes every session, access tokens included" do
      tokens = tokens_for(user)
      post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
      new_tokens = json.dig("data", "tokens")

      post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("refresh_token_reused")

      post "/api/v1/auth/refresh", params: { refresh_token: new_tokens["refresh_token"] }, as: :json
      expect(response).to have_http_status(:unauthorized)

      get "/api/v1/me", headers: bearer(new_tokens["access_token"])
      expect(response).to have_http_status(:unauthorized)
      expect(AuditLog.where(action: "auth.refresh_reuse_detected")).to exist
    end

    it "does not revoke the new session when an old device refreshes after a password change" do
      old_device = tokens_for(user)
      user.update!(password: "Nova@12345")
      new_session = tokens_for(user)

      post "/api/v1/auth/refresh", params: { refresh_token: old_device[:refresh_token] }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(AuditLog.where(action: "auth.refresh_reuse_detected")).not_to exist

      post "/api/v1/auth/refresh", params: { refresh_token: new_session[:refresh_token] }, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "invalidates old refresh tokens after an ADMIN changes the user's password" do
      admin = create(:user, :admin)
      tokens = tokens_for(user)

      patch "/api/v1/admin/users/#{user.id}", params: { password: "Trocada@123" }, headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)

      post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an unknown refresh token" do
      post "/api/v1/auth/refresh", params: { refresh_token: "not-a-real-token" }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("invalid_token")
    end

    it "rejects a refresh token issued before the password changed, even if it was not revoked" do
      tokens = tokens_for(user)
      travel(1.minute) { user.update_columns(password_changed_at: Time.current) }

      post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects the loser of two concurrent refreshes with the same token" do
      tokens = tokens_for(user)
      allow_any_instance_of(RefreshToken).to receive(:lock!).and_wrap_original do |lock, *args|
        RefreshToken.where(id: lock.receiver.id).update_all(revoked_at: Time.current, revoked_reason: "logout")
        lock.call(*args)
      end

      expect {
        post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
      }.not_to change(RefreshToken, :count)
      expect(response).to have_http_status(:unauthorized)
      expect(AuditLog.where(action: "auth.refresh_reuse_detected")).not_to exist
    end
  end

  describe "cookie mode (X-Token-Transport: cookie)" do
    let(:cookie_header) { { "X-Token-Transport" => "cookie" } }

    it "delivers the refresh token only in an httpOnly cookie and refreshes from it" do
      login(user.email, "Senha@123", headers: cookie_header)

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "tokens")).not_to have_key("refresh_token")
      set_cookie = Array(response.headers["Set-Cookie"]).join("\n")
      expect(set_cookie).to include("#{TokenResponder::REFRESH_COOKIE}=")
      expect(set_cookie).to match(/httponly/i)
      expect(set_cookie).to match(/samesite=strict/i)
      expect(set_cookie).to include("path=/api/v1/auth")

      post "/api/v1/auth/refresh", headers: cookie_header, as: :json
      expect(response).to have_http_status(:ok)
    end

    it "ignores the cookie without the custom header (CSRF protection)" do
      login(user.email, "Senha@123", headers: cookie_header)
      post "/api/v1/auth/refresh", as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "answers missing_token when there is no refresh cookie" do
      post "/api/v1/auth/refresh", headers: cookie_header, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("missing_token")
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    it "requires a token" do
      delete "/api/v1/auth/logout", as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("missing_token")
    end

    it "ends the current session immediately (access and refresh)" do
      tokens = tokens_for(user)

      delete "/api/v1/auth/logout", headers: bearer(tokens[:access_token]), as: :json
      expect(response).to have_http_status(:no_content)

      get "/api/v1/me", headers: bearer(tokens[:access_token])
      expect(response).to have_http_status(:unauthorized)
      expect(json.dig("error", "code")).to eq("token_revoked")

      post "/api/v1/auth/refresh", params: { refresh_token: tokens[:refresh_token] }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "all_devices also ends the other sessions" do
      other = tokens_for(user)
      delete "/api/v1/auth/logout", params: { all_devices: true }, headers: auth_headers(user), as: :json

      get "/api/v1/me", headers: bearer(other[:access_token])
      expect(response).to have_http_status(:unauthorized)
    end

    it "logs out a token without a session id and leaves the other sessions alive" do
      other = tokens_for(user)
      token = Auth::JsonWebToken.encode({ sub: user.id, type: "access" }, expires_at: 15.minutes.from_now)

      delete "/api/v1/auth/logout", headers: bearer(token), as: :json
      expect(response).to have_http_status(:no_content)

      get "/api/v1/me", headers: bearer(token)
      expect(response).to have_http_status(:unauthorized)
      get "/api/v1/me", headers: bearer(other[:access_token])
      expect(response).to have_http_status(:ok)
    end
  end
end
