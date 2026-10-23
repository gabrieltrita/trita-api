module Auth
  class JsonWebToken
    ALGORITHM = "HS256".freeze
    ISSUER = "#{Rails.configuration.x.app.slug}-api".freeze
    MIN_SECRET_LENGTH = 64

    class << self
      def encode(payload, expires_at:)
        now = Time.current.to_i
        claims = payload.merge(
          iss: ISSUER,
          iat: now,
          nbf: now,
          exp: expires_at.to_i,
          jti: SecureRandom.uuid
        )
        JWT.encode(claims, secrets.first, ALGORITHM)
      end

      def decode(token, type:)
        payload = nil
        secrets.each do |secret|
          payload = try_decode(token, secret)
          break if payload
        end

        raise Auth::InvalidToken if payload.nil? || payload["type"] != type

        payload
      end

      def access_ttl
        ENV.fetch("JWT_ACCESS_TTL_MINUTES", 15).to_i.minutes
      end

      def refresh_ttl
        ENV.fetch("JWT_REFRESH_TTL_DAYS", 30).to_i.days
      end

      private

      def try_decode(token, secret)
        payload, = JWT.decode(
          token, secret, true,
          algorithm: ALGORITHM,
          iss: ISSUER,
          verify_iss: true,
          required_claims: %w[exp iat jti sub type]
        )
        payload
      rescue JWT::VerificationError
        nil
      rescue JWT::DecodeError
        raise Auth::InvalidToken
      end

      def secrets
        [ ENV.fetch("JWT_SECRET"), ENV["JWT_SECRET_PREVIOUS"].presence ].compact
      end
    end
  end
end
