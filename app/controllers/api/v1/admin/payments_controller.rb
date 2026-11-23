module Api
  module V1
    module Admin
      class PaymentsController < BaseController
        def index
          authorize Payment, :manage?
          scope = Payment.recent
          scope = scope.where(status: params[:status]) if params[:status].present?
          scope = scope.where(user_id: params[:user_id]) if params[:user_id].present?

          pagy, payments = pagy(scope)
          render json: { data: PaymentBlueprint.render_as_hash(payments, view: :admin), meta: pagination_meta(pagy) }
        end

        def create
          authorize Payment, :manage?
          user = User.where.not(confirmed_at: nil).where(anonymized_at: nil).find(params.require(:user_id))
          payment = user.payments.create!(amount_cents: params[:amount_cents], description: params[:description])
          render json: { data: PaymentBlueprint.render_as_hash(payment, view: :admin) }, status: :created
        end

        def refund
          authorize Payment, :manage?
          payment = Payment.find(params[:id])
          unless payment.refundable?
            return render_error(status: :conflict, code: "payment_not_refundable", message: "Only approved payments can be refunded")
          end

          payment.apply!(Payments::Gateway.current.refund(payment))
          AuditLog.record!("payment.refunded", target: payment, metadata: { amount_cents: payment.amount_cents })
          render json: { data: PaymentBlueprint.render_as_hash(payment, view: :admin) }
        end
      end
    end
  end
end
