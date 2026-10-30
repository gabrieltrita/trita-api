module Auth
  class OauthSignin
    PRIVATE_RELAY_DOMAIN = "privaterelay.appleid.com".freeze
    DEFAULT_FIRST_NAME = "User".freeze

    class ConsentRequired < StandardError
      attr_reader :kinds

      def initialize(kinds)
        super("Required consents were not accepted")
        @kinds = kinds
      end
    end

    def self.call(provider:, claims:, consents:)
      new(provider, claims, consents).call
    end

    def initialize(provider, claims, consents)
      @provider = provider
      @claims = claims
      @consents = consents
    end

    def call
      attempt
    rescue ActiveRecord::RecordNotUnique
      attempt
    end

    private

    def attempt
      identity = Identity.find_by(provider: @provider, provider_uid: @claims.sub)
      return identity.user if identity

      user = User.find_by(email: @claims.email)
      user ? link(user) : register
    end

    def link(user)
      reclaimed = !user.confirmed?
      identity = nil

      User.transaction do
        identity = user.identities.create!(provider: @provider, provider_uid: @claims.sub, email_at_link: @claims.email)
        user.update!(password: nil, confirmed_at: Time.current) if reclaimed
        AuditLog.record!("identity.linked", target: user, actor: user, metadata: { provider: @provider.to_s, reclaimed: reclaimed })
      end

      UserMailer.identity_linked(identity).deliver_later
      user
    end

    def register
      missing = Consent.required_kinds.reject { |kind| @consents[kind] }
      raise ConsentRequired.new(missing) if missing.any?

      user = User.new(email: @claims.email, first_name: first_name, last_name: @claims.family_name&.first(100), confirmed_at: Time.current)
      user.identities.build(provider: @provider, provider_uid: @claims.sub, email_at_link: @claims.email)

      User.transaction do
        user.save!
        Consent.required_kinds.each { |kind| Consent.record!(user, kind, true) }
        Consent.record!(user, "marketing", @consents["marketing"])
        AuditLog.record!("user.registered", target: user, actor: user, metadata: { provider: @provider.to_s })
      end

      user
    end

    def first_name
      (@claims.given_name.presence || email_name).first(100)
    end

    def email_name
      return DEFAULT_FIRST_NAME if @claims.email.downcase.end_with?("@#{PRIVATE_RELAY_DOMAIN}")

      @claims.email.split("@").first
    end
  end
end
