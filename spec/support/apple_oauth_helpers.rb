module AppleOauthHelpers
  APPLE_CLIENT_ID = "com.example.app".freeze
  APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys".freeze
  APPLE_KEYS = Hash.new { |keys, kid| keys[kid] = OpenSSL::PKey::RSA.generate(2048) }

  def apple_key(kid = "apple-kid-1")
    APPLE_KEYS[kid]
  end

  def apple_jwks(*kids)
    { keys: kids.map { |kid| JWT::JWK.new(apple_key(kid), kid: kid).export } }.to_json
  end

  def stub_apple_jwks(*kids)
    kids = [ "apple-kid-1" ] if kids.empty?
    stub_request(:get, APPLE_JWKS_URL).to_return(status: 200, body: apple_jwks(*kids))
  end

  def apple_claims(overrides = {})
    {
      iss: "https://appleid.apple.com",
      aud: APPLE_CLIENT_ID,
      sub: "apple-sub-1",
      email: "person@example.com",
      email_verified: "true",
      is_private_email: "false",
      iat: Time.now.to_i,
      exp: 1.hour.from_now.to_i
    }.merge(overrides).compact
  end

  def apple_id_token(kid: "apple-kid-1", **overrides)
    JWT.encode(apple_claims(overrides), apple_key(kid), "RS256", { kid: kid })
  end
end

RSpec.shared_context "with apple oauth" do
  include AppleOauthHelpers

  around do |example|
    original = ENV["APPLE_CLIENT_IDS"]
    ENV["APPLE_CLIENT_IDS"] = "#{AppleOauthHelpers::APPLE_CLIENT_ID},com.example.web"
    example.run
  ensure
    original ? ENV["APPLE_CLIENT_IDS"] = original : ENV.delete("APPLE_CLIENT_IDS")
  end

  before { stub_apple_jwks }
end
