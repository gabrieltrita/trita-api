class PaymentReconciliationJob < ApplicationJob
  queue_as :default

  def perform
    return unless Payments::Gateway.enabled?

    Payment.stale_pending.find_each { |payment| PaymentSyncJob.perform_later(payment) }
  end
end
