class AuditLog < ApplicationRecord
  ACTIONS = %w[
    auth.login auth.login_failed auth.login_blocked auth.locked auth.logout
    auth.two_factor_failed auth.refresh_reuse_detected
    user.registered user.confirmed user.created user.updated user.anonymized
    user.role_changed user.password_changed user.password_reset_requested user.password_reset
    user.email_change_requested user.email_changed user.unlocked user.deactivated user.reactivated
    user.data_exported user.consent_changed
    two_factor.enabled two_factor.disabled two_factor.reset two_factor.backup_codes_regenerated
    session.revoked identity.linked identity.unlinked
    payment.created payment.attempted payment.status_changed payment.refunded
  ].freeze

  belongs_to :actor, class_name: "User", optional: true

  encrypts :ip_address, :user_agent

  validates :action, inclusion: { in: ACTIONS }

  scope :recent, -> { order(created_at: :desc) }
  scope :involving, ->(user) { where(actor_id: user.id).or(where(target_type: "User", target_id: user.id)) }

  def readonly?
    persisted?
  end

  def self.record!(action, target: nil, actor: Current.user, metadata: {})
    create!(
      action: action,
      actor: actor,
      target_type: target&.class&.name,
      target_id: target&.id,
      metadata: metadata,
      ip_address: Current.ip_address,
      user_agent: Current.user_agent&.truncate(500),
      request_id: Current.request_id
    )
  rescue => e
    Rails.logger.error({ message: "AuditLog failed to record", action: action, error: e.class.name })
    Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
    nil
  end
end
