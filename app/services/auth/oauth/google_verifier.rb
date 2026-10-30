module Auth
  module Oauth
    class GoogleVerifier < JwksVerifier
      PROVIDER = "google".freeze
      PROVIDER_NAME = "Google".freeze
      JWKS_URI = URI("https://www.googleapis.com/oauth2/v3/certs").freeze
      ISSUERS = %w[https://accounts.google.com accounts.google.com].freeze
      CLIENT_IDS_ENV = "GOOGLE_CLIENT_IDS".freeze
    end
  end
end
