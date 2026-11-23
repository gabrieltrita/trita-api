module MercadoPagoHelpers
  ACCESS_TOKEN = "TEST-access-token".freeze
  WEBHOOK_SECRET = "test-webhook-secret".freeze
  PAYMENTS_URL = "https://api.mercadopago.com/v1/payments".freeze

  def mercado_pago_payment(overrides = {})
    {
      "id" => 1_234_567,
      "status" => "approved",
      "status_detail" => "accredited",
      "payment_method_id" => "visa",
      "installments" => 1,
      "card" => { "last_four_digits" => "4242" }
    }.merge(overrides)
  end

  def mercado_pago_pix(overrides = {})
    {
      "id" => 7_654_321,
      "status" => "pending",
      "status_detail" => "pending_waiting_transfer",
      "payment_method_id" => "pix",
      "installments" => 1,
      "date_of_expiration" => "2026-11-23T12:30:00.000-03:00",
      "point_of_interaction" => {
        "transaction_data" => { "qr_code" => "00020126pix", "qr_code_base64" => "iVBORw0KGgo=", "ticket_url" => "https://www.mercadopago.com.br/payments/7654321/ticket" }
      }
    }.merge(overrides)
  end

  def stub_mercado_pago_create(body, status: 201)
    stub_request(:post, PAYMENTS_URL).to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_mercado_pago_fetch(body, status: 200)
    stub_request(:get, "#{PAYMENTS_URL}/#{body['id']}").to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def mercado_pago_signature(data_id, request_id: "req-1", ts: "1700000000", secret: WEBHOOK_SECRET)
    manifest = "id:#{data_id.to_s.downcase};#{"request-id:#{request_id};" if request_id}ts:#{ts};"
    "ts=#{ts},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, manifest)}"
  end
end

RSpec.configure do |config|
  config.include MercadoPagoHelpers

  config.around(:each, :mercado_pago) do |example|
    originals = %w[MERCADO_PAGO_ACCESS_TOKEN MERCADO_PAGO_WEBHOOK_SECRET].index_with { |key| ENV[key] }
    ENV["MERCADO_PAGO_ACCESS_TOKEN"] = MercadoPagoHelpers::ACCESS_TOKEN
    ENV["MERCADO_PAGO_WEBHOOK_SECRET"] = MercadoPagoHelpers::WEBHOOK_SECRET
    example.run
  ensure
    originals.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end
end
