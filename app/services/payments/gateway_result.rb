module Payments
  GatewayResult = Data.define(
    :provider, :provider_payment_id, :status, :status_detail, :payment_method, :installments,
    :card_brand, :card_last_four, :pix_qr_code, :pix_qr_code_base64, :pix_ticket_url, :pix_expires_at
  )
end
