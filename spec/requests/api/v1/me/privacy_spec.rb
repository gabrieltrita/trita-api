require "rails_helper"

RSpec.describe "LGPD: consents and data export", type: :request do
  let(:user) { create(:user, email: "titular@example.com") }

  before do
    Consent.record!(user, "terms", true)
    Consent.record!(user, "privacy", true)
  end

  describe "consents" do
    it "shows the current status of each kind" do
      get "/api/v1/me/consents", headers: auth_headers(user)
      expect(json.dig("data", "terms", "granted")).to be(true)
      expect(json.dig("data", "marketing", "granted")).to be(false)
    end

    it "records the change as a new row (history) and audits it" do
      expect {
        post "/api/v1/me/consents", params: { kind: "marketing", granted: true }, headers: auth_headers(user), as: :json
      }.to change(Consent, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "marketing", "granted")).to be(true)
      expect(AuditLog.where(action: "user.consent_changed", target_id: user.id)).to exist
    end

    it "keeps the device user agent as evidence of the consent" do
      post "/api/v1/me/consents", params: { kind: "marketing", granted: true }, headers: auth_headers(user).merge("User-Agent" => "TestAgent/1.0"), as: :json
      expect(user.consents.order(:created_at).last.user_agent).to eq("TestAgent/1.0")
    end

    it "does not allow revoking a required consent" do
      post "/api/v1/me/consents", params: { kind: "terms", granted: false }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("consent_required")
    end

    it "rejects an unknown kind" do
      post "/api/v1/me/consents", params: { kind: "outro", granted: true }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/me/export" do
    it "exports all of the data subject's data as a JSON attachment and audits it" do
      tokens_for(user)
      get "/api/v1/me/export", headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Disposition"]).to eq(%(attachment; filename="#{Rails.configuration.x.app.slug}-data-#{Date.current.iso8601}.json"))
      expect(json.keys).to include("exported_at", "profile", "consents", "sessions", "activity")
      expect(json.dig("profile", "email")).to eq("titular@example.com")
      expect(json["consents"].size).to eq(2)
      expect(json["profile"].keys).not_to include("password_digest", "otp_secret")
      expect(AuditLog.where(action: "user.data_exported", target_id: user.id)).to exist
    end
  end
end
