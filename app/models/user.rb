class User < ApplicationRecord
  include TwoFactorAuthenticatable

  PASSWORD_FORMAT = /\A(?=.*[a-z])(?=.*[A-Z])(?=.*\d).+\z/
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  MAX_FAILED_ATTEMPTS = 5
  BASE_LOCK_DURATION = 15.minutes
  MAX_LOCK_DURATION = 24.hours

  PERSONAL_DATA = %i[notes identities].freeze

  DEFAULT_TIME_ZONE = "America/Sao_Paulo"
  TIME_ZONES = TZInfo::Timezone.all_identifiers.to_set.freeze

  has_secure_password reset_token: false, validations: false

  has_many :refresh_tokens, dependent: :delete_all
  has_many :consents, dependent: :delete_all
  has_many :notes, dependent: :destroy
  has_many :identities, dependent: :destroy
  has_many :payments, dependent: :restrict_with_exception

  encrypts :email, deterministic: true, downcase: true
  encrypts :first_name, :last_name, :phone, :unconfirmed_email, :otp_secret

  enum :role, { user: 0, admin: 1 }, default: :user, validate: true

  generates_token_for :password_reset, expires_in: 30.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_confirmation, expires_in: 24.hours do
    [ email, confirmed_at ]
  end

  generates_token_for :email_change, expires_in: 24.hours do
    unconfirmed_email
  end

  normalizes :email, :unconfirmed_email, with: ->(email) { email.strip.downcase }
  normalizes :first_name, :last_name, with: ->(value) { value.strip.squish }
  normalizes :phone, with: ->(value) { value.gsub(/[^\d+]/, "") }

  validates :email, presence: true, uniqueness: true, format: { with: EMAIL_FORMAT }, length: { maximum: 255 }
  validates :unconfirmed_email, format: { with: EMAIL_FORMAT }, length: { maximum: 255 }, allow_nil: true
  validates :first_name, presence: true, length: { maximum: 100 }
  validates :last_name, length: { maximum: 100 }
  validates :phone, length: { maximum: 20 }
  validates :time_zone, inclusion: { in: TIME_ZONES }
  validates :password, length: { minimum: 8, maximum: 72 }, format: { with: PASSWORD_FORMAT, message: :weak_password }, if: -> { password.present? }

  validates :password, confirmation: true, allow_blank: true
  validate :password_or_identity_present

  scope :not_anonymized, -> { where(anonymized_at: nil) }
  scope :deactivated, -> { where.not(deactivated_at: nil) }
  scope :not_deactivated, -> { where(deactivated_at: nil) }

  before_save :track_password_change, if: :will_save_change_to_password_digest?
  after_update_commit :on_password_changed, if: :saved_change_to_password_digest?
  after_update_commit :on_role_changed, if: :saved_change_to_role?
  after_update_commit :on_email_changed, if: :saved_change_to_email?

  def self.roles_list
    roles.keys
  end

  def full_name
    [ first_name, last_name ].compact_blank.join(" ")
  end

  def password_set?
    password_digest.present?
  end

  def login_methods_count
    identities.count + (password_set? ? 1 : 0)
  end

  def anonymized?
    anonymized_at.present?
  end

  def confirmed?
    confirmed_at.present?
  end

  def confirm!
    update!(confirmed_at: Time.current) unless confirmed?
  end

  def confirm_email_change!
    raise ActiveRecord::RecordInvalid, self if unconfirmed_email.blank?

    self.email = unconfirmed_email
    self.unconfirmed_email = nil
    self.confirmed_at = Time.current
    save!
  end

  def track_sign_in!
    update_columns(last_sign_in_at: Time.current, sign_in_count: sign_in_count + 1)
  end

  def revoke_all_sessions!(except_family: nil, reason: "sessions_revoked")
    scope = refresh_tokens.active
    scope = scope.where.not(family_id: except_family) if except_family
    scope.distinct.pluck(:family_id).each { |family_id| Auth::TokenDenylist.revoke_session(family_id) }
    scope.update_all(revoked_at: Time.current, revoked_reason: reason)
  end

  def revoke_session!(family_id, reason: "session_revoked")
    Auth::TokenDenylist.revoke_session(family_id)
    refresh_tokens.where(family_id: family_id, revoked_at: nil).update_all(revoked_at: Time.current, revoked_reason: reason)
  end

  def deactivated?
    deactivated_at.present?
  end

  def deactivate!
    update_columns(deactivated_at: Time.current, updated_at: Time.current)
    revoke_all_sessions!(reason: "deactivated")
  end

  def reactivate!
    update_columns(deactivated_at: nil, updated_at: Time.current)
  end

  def access_locked?
    locked_until.present? && locked_until.future?
  end

  def register_failed_login!
    increment!(:failed_login_attempts, touch: false)
    return if failed_login_attempts < MAX_FAILED_ATTEMPTS

    exponent = [ failed_login_attempts - MAX_FAILED_ATTEMPTS, 10 ].min
    duration = [ BASE_LOCK_DURATION * (2**exponent), MAX_LOCK_DURATION ].min
    update_columns(locked_until: duration.from_now)

    AuditLog.record!("auth.locked", target: self, actor: nil, metadata: { attempts: failed_login_attempts, minutes: (duration / 60).to_i })
    UserMailer.account_locked(self).deliver_later
  end

  def reset_failed_logins!
    return if failed_login_attempts.zero? && locked_until.nil?

    update_columns(failed_login_attempts: 0, locked_until: nil)
  end
  alias_method :unlock!, :reset_failed_logins!

  def anonymize!
    transaction do
      revoke_all_sessions!(reason: "anonymized")
      PERSONAL_DATA.each { |association| public_send(association).destroy_all }
      update_columns(
        email: "anon-#{id}@anonymized.invalid",
        first_name: "Deleted",
        last_name: "user",
        phone: nil,
        time_zone: DEFAULT_TIME_ZONE,
        unconfirmed_email: nil,
        otp_secret: nil,
        otp_enabled_at: nil,
        otp_last_used_step: nil,
        otp_backup_code_digests: [],
        password_digest: BCrypt::Password.create(SecureRandom.hex(32)),
        failed_login_attempts: 0,
        locked_until: nil,
        anonymized_at: Time.current,
        updated_at: Time.current
      )
    end
  end

  private

  def password_or_identity_present
    return if password_set? || identities.any?

    errors.add(:password, :blank)
  end

  def track_password_change
    self.password_changed_at = Time.current if persisted?
  end

  def on_password_changed
    revoke_all_sessions!(reason: "password_changed")
    reset_failed_logins!
    AuditLog.record!("user.password_changed", target: self)
    UserMailer.password_changed(self).deliver_later
  end

  def on_role_changed
    from, to = saved_change_to_role
    AuditLog.record!("user.role_changed", target: self, metadata: { from: from, to: to })
  end

  def on_email_changed
    AuditLog.record!("user.email_changed", target: self)
  end
end
