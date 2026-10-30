require "rails_helper"

RSpec.describe "Auth::Oauth (Apple)", type: :request do
  include_context "with apple oauth"

  let(:consents) { { accept_terms: true, accept_privacy: true } }

  def apple_login(token = apple_id_token, extra: {})
    post "/api/v1/auth/oauth/apple", params: { id_token: token }.merge(extra), as: :json
  end

  it "logs in an account already linked to the Apple user" do
    identity = create(:identity, provider: :apple, provider_uid: "apple-sub-1", user: create(:user, email: "other@example.com"))

    apple_login

    expect(response).to have_http_status(:ok)
    expect(json.dig("data", "user", "id")).to eq(identity.user_id)
    expect(AuditLog.find_by(action: "auth.login", target_id: identity.user_id).metadata).to include("provider" => "apple")
  end

  it "links the identity to a confirmed account that has the same real email" do
    user = create(:user, email: "person@example.com")

    expect { apple_login }.to have_enqueued_mail(UserMailer, :identity_linked)

    expect(response).to have_http_status(:ok)
    expect(user.identities.pluck(:provider)).to eq([ "apple" ])
  end

  it "creates the account with the name the client sends, because the token has none" do
    apple_login(extra: consents.merge(first_name: "Maria", last_name: "Silva"))

    user = User.find_by(email: "person@example.com")
    expect(user).to have_attributes(first_name: "Maria", last_name: "Silva")
    expect(user.identities.first.provider).to eq("apple")
  end

  it "ignores a name that is not plain text" do
    apple_login(extra: consents.merge(first_name: { nested: "x" }, last_name: [ "x" ]))

    expect(response).to have_http_status(:ok)
    expect(User.find_by(email: "person@example.com")).to have_attributes(first_name: "person", last_name: nil)
  end

  it "creates a separate account for a private relay address and names it User" do
    existing = create(:user, email: "person@example.com")

    apple_login(apple_id_token(email: "x7k2m9@privaterelay.appleid.com", is_private_email: "true"), extra: consents)

    expect(response).to have_http_status(:ok)
    created = User.find_by(email: "x7k2m9@privaterelay.appleid.com")
    expect(created).to be_confirmed
    expect(created.first_name).to eq("User")
    expect(existing.identities).to be_empty
  end

  it "requires the consents when the account is new" do
    apple_login

    expect(response).to have_http_status(:unprocessable_content)
    expect(json.dig("error", "details").keys).to contain_exactly("accept_terms", "accept_privacy")
  end

  it "rejects an invalid token and an unverified email" do
    apple_login("garbage")
    expect(json.dig("error", "code")).to eq("oauth_token_invalid")

    apple_login(apple_id_token(email_verified: "false"), extra: consents)
    expect(json.dig("error", "code")).to eq("oauth_email_unverified")
  end

  it "answers 503 when Apple's keys cannot be fetched" do
    stub_request(:get, AppleOauthHelpers::APPLE_JWKS_URL).to_return(status: 500)

    apple_login

    expect(response).to have_http_status(:service_unavailable)
    expect(json.dig("error", "code")).to eq("oauth_provider_unavailable")
  end
end
