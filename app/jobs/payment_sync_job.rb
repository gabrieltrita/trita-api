class PaymentSyncJob < ApplicationJob
  queue_as :default

  retry_on Payments::GatewayUnavailable, wait: :polynomially_longer, attempts: 5

  def perform(payment)
    payment.apply!(Payments::Gateway.current.fetch(payment.provider_payment_id))
  end
end
