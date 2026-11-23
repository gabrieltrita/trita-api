module Api
  module V1
    module Webhooks
      class MercadoPagoController < ApplicationController
        skip_before_action :authenticate_user!

        def create
          data_id = params.dig(:data, :id).to_s
          signed = Payments::WebhookSignature.valid?(header: request.headers["x-signature"], request_id: request.headers["x-request-id"], data_id: data_id)
          return render_error(status: :unauthorized, code: "webhook_signature_invalid", message: "Invalid webhook signature") unless signed

          payment = Payment.find_by(provider: Payments::Gateways::MercadoPago::PROVIDER, provider_payment_id: data_id)
          PaymentSyncJob.perform_later(payment) if payment
          head :ok
        end
      end
    end
  end
end
