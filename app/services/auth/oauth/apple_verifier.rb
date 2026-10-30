module Auth
  module Oauth
    class AppleVerifier < JwksVerifier
      PROVIDER = "apple".freeze
      PROVIDER_NAME = "Apple".freeze
      JWKS_URI = URI("https://appleid.apple.com/auth/keys").freeze
      ISSUERS = %w[https://appleid.apple.com].freeze
      CLIENT_IDS_ENV = "APPLE_CLIENT_IDS".freeze
    end
  end
end
