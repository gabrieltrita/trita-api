class Payment < ApplicationRecord
  STATUSES = %w[created pending approved rejected cancelled refunded charged_back].freeze
  PAYMENT_METHODS = %w[pix card].freeze
  PAYABLE_STATUSES = %w[created rejected].freeze
  CURRENCIES = %w[BRL].freeze
  MAX_AMOUNT_CENTS = 100_000_000
  STALE_AFTER = 15.minutes

  belongs_to :user
  belongs_to :payable, polymorphic: true, optional: true

  enum :status, STATUSES.index_by(&:itself), validate: true

  normalizes :description, with: ->(value) { value.squish }

  validates :amount_cents, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_AMOUNT_CENTS }
  validates :currency, inclusion: { in: CURRENCIES }
  validates :description, presence: true, length: { maximum: 200 }
  validates :payment_method, inclusion: { in: PAYMENT_METHODS }, allow_nil: true

  after_create { AuditLog.record!("payment.created", target: self, metadata: { amount_cents: amount_cents, currency: currency }) }

  scope :recent, -> { order(created_at: :desc) }
  scope :stale_pending, -> { pending.where(updated_at: ...STALE_AFTER.ago) }

  def payable?
    PAYABLE_STATUSES.include?(status)
  end

  def refundable?
    approved?
  end

  def apply!(result)
    previous = status
    assign_attributes(result.to_h.compact)
    self.approved_at ||= Time.current if approved?
    self.refunded_at ||= Time.current if refunded?
    save!
    return if previous == status

    AuditLog.record!("payment.status_changed", target: self, metadata: { from: previous, to: status, payment_method: payment_method })
  end
end
