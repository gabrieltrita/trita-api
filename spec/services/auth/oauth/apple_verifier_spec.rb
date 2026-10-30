require "rails_helper"

RSpec.describe Auth::Oauth::AppleVerifier do
  include_context "with apple oauth"

  def error_code
    described_class.call(yield)
  rescue Auth::Unauthorized => e
    e.code
  end

  it "returns the verified claims, without a name, accepting the string email_verified Apple sends" do
    claims = described_class.call(apple_id_token)

    expect(claims).to have_attributes(sub: "apple-sub-1", email: "person@example.com", given_name: nil, family_name: nil)
  end

  it "accepts a private relay address and the web Services ID" do
    claims = described_class.call(apple_id_token(aud: "com.example.web", email: "x7k2@privaterelay.appleid.com", is_private_email: "true"))
    expect(claims.email).to eq("x7k2@privaterelay.appleid.com")
  end

  it "rejects another issuer, another client and an expired token" do
    expect(error_code { apple_id_token(iss: "https://accounts.google.com") }).to eq("oauth_token_invalid")
    expect(error_code { apple_id_token(aud: "com.someone.else") }).to eq("oauth_token_invalid")
    expect(error_code { apple_id_token(exp: 1.minute.ago.to_i) }).to eq("oauth_token_invalid")
  end

  it "rejects a token signed with another key and every token when no client id is configured" do
    forged = JWT.encode(apple_claims, apple_key("attacker"), "RS256", { kid: "apple-kid-1" })
    expect(error_code { forged }).to eq("oauth_token_invalid")

    ENV["APPLE_CLIENT_IDS"] = ""
    expect(error_code { apple_id_token }).to eq("oauth_token_invalid")
  end

  it "rejects an unverified email" do
    expect(error_code { apple_id_token(email_verified: "false") }).to eq("oauth_email_unverified")
  end

  it "keeps its keys in its own cache entry" do
    2.times { described_class.call(apple_id_token) }

    expect(a_request(:get, AppleOauthHelpers::APPLE_JWKS_URL)).to have_been_made.once
    expect(Rails.cache.exist?("oauth/apple/jwks")).to be(true)
    expect(Rails.cache.exist?("oauth/google/jwks")).to be(false)
  end

  it "raises ProviderUnavailable naming Apple in the log when the keys cannot be fetched" do
    allow(Rails.logger).to receive(:warn)
    stub_request(:get, AppleOauthHelpers::APPLE_JWKS_URL).to_timeout

    expect { described_class.call(apple_id_token) }.to raise_error(Auth::ProviderUnavailable)
    expect(Rails.logger).to have_received(:warn).with({ message: "Apple JWKS fetch failed", error: "Net::OpenTimeout" })
  end
end
