module Auth
  module Oauth
    class JwksVerifier
      ALGORITHM = "RS256".freeze
      DEFAULT_JWKS_TTL = 1.hour
      REFRESH_COOLDOWN = 1.minute
      HTTP_TIMEOUT = 3
      FETCH_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, JSON::ParserError ].freeze

      Claims = Data.define(:sub, :email, :given_name, :family_name)

      def self.call(id_token)
        new.call(id_token)
      end

      def call(id_token)
        payload, = JWT.decode(
          id_token.to_s, nil, true,
          algorithms: [ ALGORITHM ],
          jwks: method(:jwks),
          iss: self.class::ISSUERS, verify_iss: true,
          aud: client_ids, verify_aud: true,
          required_claims: %w[exp iss aud sub]
        )

        unless payload["email"].present? && ActiveModel::Type::Boolean.new.cast(payload["email_verified"]) == true
          raise Unauthorized.new("The #{self.class::PROVIDER_NAME} email is not verified", code: "oauth_email_unverified")
        end

        Claims.new(sub: payload["sub"], email: payload["email"], given_name: payload["given_name"], family_name: payload["family_name"])
      rescue JWT::DecodeError
        raise Unauthorized.new("Invalid #{self.class::PROVIDER_NAME} token", code: "oauth_token_invalid")
      end

      private

      def client_ids
        ENV.fetch(self.class::CLIENT_IDS_ENV, "").split(",").map(&:strip).compact_blank
      end

      def jwks(options)
        if options[:invalidate] && Rails.cache.write(cache_key("jwks_refresh"), true, expires_in: REFRESH_COOLDOWN, unless_exist: true)
          return fetch_jwks
        end

        Rails.cache.read(cache_key("jwks")) || fetch_jwks
      end

      def fetch_jwks
        uri = self.class::JWKS_URI
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
          http.get(uri.request_uri)
        end
        raise ProviderUnavailable unless response.is_a?(Net::HTTPSuccess)

        keys = JSON.parse(response.body)
        Rails.cache.write(cache_key("jwks"), keys, expires_in: jwks_ttl(response))
        keys
      rescue *FETCH_ERRORS => e
        Rails.logger.warn({ message: "#{self.class::PROVIDER_NAME} JWKS fetch failed", error: e.class.name })
        raise ProviderUnavailable
      end

      def jwks_ttl(response)
        max_age = response["cache-control"].to_s[/max-age=(\d+)/, 1]
        max_age ? max_age.to_i.seconds : DEFAULT_JWKS_TTL
      end

      def cache_key(name)
        "oauth/#{self.class::PROVIDER}/#{name}"
      end
    end
  end
end
