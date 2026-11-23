class PaymentBlueprint < Blueprinter::Base
  identifier :id

  fields :amount_cents, :currency, :description, :status, :status_detail, :payment_method, :installments,
         :card_brand, :card_last_four, :pix_qr_code, :pix_qr_code_base64, :pix_ticket_url, :pix_expires_at,
         :approved_at, :refunded_at, :created_at, :updated_at

  view :admin do
    fields :user_id, :payable_type, :payable_id, :provider, :provider_payment_id
  end
end
