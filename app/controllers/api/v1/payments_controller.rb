module Api
  module V1
    class PaymentsController < ApplicationController
      include Paginatable

      MAX_INSTALLMENTS = 12

      before_action :set_payment, only: %i[show pix card]

      def index
        authorize Payment
        pagy, payments = pagy(policy_scope(Payment).recent)
        render json: { data: PaymentBlueprint.render_as_hash(payments), meta: pagination_meta(pagy) }
      end

      def show
        render json: { data: PaymentBlueprint.render_as_hash(@payment) }
      end

      def pix
        attempt!("pix") { |gateway| gateway.create_pix(@payment, payer: payer) }
      end

      def card
        token = params.require(:card_token)
        payment_method_id = params.require(:payment_method_id)

        attempt!("card") do |gateway|
          gateway.create_card(@payment, payer: payer, token: token, payment_method_id: payment_method_id,
                                        issuer_id: params[:issuer_id].presence, installments: installments)
        end
      end

      private

      def set_payment
        @payment = policy_scope(Payment).find(params[:id])
        authorize @payment
      end

      def attempt!(payment_method)
        unless @payment.payable?
          return render_error(status: :conflict, code: "payment_not_payable", message: "This payment cannot be paid now")
        end

        result = yield Payments::Gateway.current
        AuditLog.record!("payment.attempted", target: @payment, metadata: { payment_method: payment_method })
        @payment.apply!(result)
        render json: { data: PaymentBlueprint.render_as_hash(@payment) }
      end

      def payer
        { email: current_user.email, document: params[:payer_document].to_s.gsub(/\D/, "").presence }
      end

      def installments
        params.fetch(:installments, 1).to_i.clamp(1, MAX_INSTALLMENTS)
      end
    end
  end
end
