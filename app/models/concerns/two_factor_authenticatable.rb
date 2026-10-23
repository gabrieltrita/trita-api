module TwoFactorAuthenticatable
  extend ActiveSupport::Concern

  OTP_ISSUER = Rails.configuration.x.app.name.freeze
  OTP_DRIFT = 30
  BACKUP_CODES_COUNT = 10

  def two_factor_enabled?
    otp_enabled_at.present?
  end

  def two_factor_setup_required?
    admin? && !two_factor_enabled?
  end

  def generate_otp_secret!
    update!(otp_secret: ROTP::Base32.random, otp_enabled_at: nil, otp_last_used_step: nil)
  end

  def otp_provisioning_uri
    totp.provisioning_uri(email)
  end

  def enable_two_factor!(code)
    return if otp_secret.blank? || two_factor_enabled?
    return unless verify_otp(code)

    codes = new_backup_codes
    update!(otp_enabled_at: Time.current, otp_backup_code_digests: codes.map { |c| backup_code_digest(c) })
    codes
  end

  def disable_two_factor!
    update!(otp_secret: nil, otp_enabled_at: nil, otp_last_used_step: nil, otp_backup_code_digests: [])
  end

  def regenerate_backup_codes!
    codes = new_backup_codes
    update!(otp_backup_code_digests: codes.map { |c| backup_code_digest(c) })
    codes
  end

  def backup_codes_remaining
    otp_backup_code_digests.size
  end

  def verify_second_factor(code)
    verify_otp(code) || consume_backup_code(code)
  end

  def verify_otp(code)
    normalized = code.to_s.gsub(/\s/, "")
    return false if otp_secret.blank? || normalized !~ /\A\d{6}\z/

    timestamp = totp.verify(normalized, drift_behind: OTP_DRIFT, drift_ahead: OTP_DRIFT, after: otp_last_used_step)
    return false unless timestamp

    update_columns(otp_last_used_step: timestamp)
    true
  end

  private

  def totp
    ROTP::TOTP.new(otp_secret, issuer: OTP_ISSUER)
  end

  def consume_backup_code(code)
    normalized = code.to_s.downcase.gsub(/[^a-z0-9]/, "")
    return false if normalized.length != 10

    digest = backup_code_digest(normalized)
    match = otp_backup_code_digests.find { |stored| ActiveSupport::SecurityUtils.secure_compare(stored, digest) }
    return false unless match

    update_columns(otp_backup_code_digests: otp_backup_code_digests - [ match ])
    true
  end

  def new_backup_codes
    Array.new(BACKUP_CODES_COUNT) { SecureRandom.alphanumeric(10).downcase }
  end

  def backup_code_digest(code)
    key = Rails.application.key_generator.generate_key("two_factor/backup_codes", 32)
    OpenSSL::HMAC.hexdigest("SHA256", key, code.to_s.downcase.gsub(/[^a-z0-9]/, ""))
  end
end
