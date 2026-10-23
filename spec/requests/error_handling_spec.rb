require "rails_helper"

RSpec.describe "Error handling", type: :request do
  it "turns a validation failure raised mid-request into per-field errors" do
    user = create(:user, email: "owner@example.com")
    user.update!(unconfirmed_email: "wanted@example.com")
    token = user.generate_token_for(:email_change)
    create(:user, email: "wanted@example.com")

    post "/api/v1/auth/email/confirm", params: { token: token }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "code")).to eq("validation_failed")
    expect(json.dig("error", "details", "email", 0, "code")).to eq("taken")
    expect(user.reload.email).to eq("owner@example.com")
  end
end
