class EnvValidator
  REQUIRED = %w[
    DATABASE_URL REDIS_URL SIDEKIQ_REDIS_URL
    SECRET_KEY_BASE JWT_SECRET AR_ENCRYPTION_PRIMARY_KEY AR_ENCRYPTION_DETERMINISTIC_KEY AR_ENCRYPTION_KEY_DERIVATION_SALT
    APP_HOSTS CORS_ORIGINS FRONTEND_URL MAILER_FROM SMTP_ADDRESS
    SIDEKIQ_WEB_USERNAME SIDEKIQ_WEB_PASSWORD
  ].freeze

  ENCRYPTION_KEYS = %w[AR_ENCRYPTION_PRIMARY_KEY AR_ENCRYPTION_DETERMINISTIC_KEY AR_ENCRYPTION_KEY_DERIVATION_SALT].freeze

  MIN_SECRET_KEY_BASE = 64
  MIN_JWT_SECRET = 64
  MIN_ENCRYPTION_KEY = 32
  MIN_SIDEKIQ_PASSWORD = 16
  APPLE_REVOCATION_KEYS = %w[APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY].freeze

  def self.validate!(env = ENV)
    errors = new(env).errors
    raise "Invalid production configuration:\n  - #{errors.join("\n  - ")}" if errors.any?
  end

  def initialize(env)
    @env = env
  end

  def errors
    errors = REQUIRED.select { |key| blank?(key) }.map { |key| "#{key} is not set" }

    if present?("SECRET_KEY_BASE") && @env["SECRET_KEY_BASE"].length < MIN_SECRET_KEY_BASE
      errors << "SECRET_KEY_BASE must be at least #{MIN_SECRET_KEY_BASE} characters"
    end

    if present?("JWT_SECRET") && @env["JWT_SECRET"].length < MIN_JWT_SECRET
      errors << "JWT_SECRET must be at least #{MIN_JWT_SECRET} characters"
    end

    ENCRYPTION_KEYS.each do |key|
      next if blank?(key)

      if @env[key].split(",").any? { |k| k.strip.length < MIN_ENCRYPTION_KEY }
        errors << "#{key} must be at least #{MIN_ENCRYPTION_KEY} characters"
      end
    end

    if present?("SIDEKIQ_WEB_PASSWORD") && @env["SIDEKIQ_WEB_PASSWORD"].length < MIN_SIDEKIQ_PASSWORD
      errors << "SIDEKIQ_WEB_PASSWORD must be at least #{MIN_SIDEKIQ_PASSWORD} characters"
    end

    origins = @env["CORS_ORIGINS"].to_s.split(",").map(&:strip)
    errors << "CORS_ORIGINS must not contain *" if origins.include?("*")
    errors << "CORS_ORIGINS must use https in production" if origins.any? { |o| !o.start_with?("https://") }

    apple_missing = APPLE_REVOCATION_KEYS.select { |key| blank?(key) }
    if apple_missing.any? && apple_missing.size < APPLE_REVOCATION_KEYS.size
      errors << "#{APPLE_REVOCATION_KEYS.join(', ')} must be set together (missing: #{apple_missing.join(', ')})"
    end

    errors
  end

  private

  def blank?(key)
    @env[key].to_s.strip.empty?
  end

  def present?(key)
    !blank?(key)
  end
end
