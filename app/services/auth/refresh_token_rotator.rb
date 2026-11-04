module Auth
  class RefreshTokenRotator
    def self.call(raw_token, request: nil)
      new(raw_token, request).call
    end

    def initialize(raw_token, request)
      @raw_token = raw_token
      @request = request
    end

    def call
      record = RefreshToken.find_by_raw_token(@raw_token)
      raise InvalidToken if record.nil?

      user = record.user

      if record.rotated?
        user.revoke_all_sessions!(reason: "reuse_detected")
        AuditLog.record!("auth.refresh_reuse_detected", target: user, actor: nil)
        raise InvalidToken.new("Refresh token reused. Every session has been revoked.", code: "refresh_token_reused")
      end

      raise InvalidToken if record.revoked? || record.expired? || user.anonymized? || user.deactivated?
      raise InvalidToken if user.password_changed_at && record.created_at < user.password_changed_at

      RefreshToken.transaction do
        record.lock!
        raise InvalidToken if record.revoked?

        record.revoke!(reason: RefreshToken::ROTATED)
        tokens = TokenIssuer.call(user, request: @request, family_id: record.family_id, session_started_at: record.session_started_at)
        [ user, tokens ]
      end
    end
  end
end
