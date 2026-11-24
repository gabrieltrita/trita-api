require "rails_helper"

RSpec.describe Payments::Gateways::MercadoPago do
  subject(:gateway) { described_class.new(access_token: MercadoPagoHelpers::ACCESS_TOKEN) }

  let(:payment) { create(:payment, amount_cents: 15_050, description: "Logo design") }
  let(:payer) { { email: "client@example.com", document: "12345678909" } }

  describe "#create_pix" do
    it "creates the charge with an idempotency key and maps the QR code" do
      stub = stub_mercado_pago_create(mercado_pago_pix).with do |request|
        body = JSON.parse(request.body)
        request.headers["Authorization"] == "Bearer #{MercadoPagoHelpers::ACCESS_TOKEN}" &&
          request.headers["X-Idempotency-Key"].start_with?("#{payment.id}-pix-") &&
          body["transaction_amount"] == 150.5 && body["payment_method_id"] == "pix" && body["external_reference"] == payment.id &&
          body["payer"] == { "email" => "client@example.com", "identification" => { "type" => "CPF", "number" => "12345678909" } } &&
          body["date_of_expiration"].present?
      end

      result = gateway.create_pix(payment, payer: payer)

      expect(stub).to have_been_requested
      expect(result).to have_attributes(
        provider: "mercado_pago", provider_payment_id: "7654321", status: "pending", payment_method: "pix", card_brand: nil,
        pix_qr_code: "00020126pix", pix_qr_code_base64: "iVBORw0KGgo=", pix_expires_at: "2026-11-23T12:30:00.000-03:00"
      )
    end
  end

  describe "#create_card" do
    it "sends the token and installments, without an identification when there is no document" do
      stub = stub_mercado_pago_create(mercado_pago_payment).with do |request|
        body = JSON.parse(request.body)
        body.slice("token", "payment_method_id", "installments") == { "token" => "tok", "payment_method_id" => "visa", "installments" => 3 } &&
          !body.key?("issuer_id") && body["payer"] == { "email" => "client@example.com" }
      end

      result = gateway.create_card(payment, payer: { email: "client@example.com", document: nil }, token: "tok", payment_method_id: "visa", issuer_id: nil, installments: 3)

      expect(stub).to have_been_requested
      expect(result).to have_attributes(status: "approved", payment_method: "card", card_brand: "visa", card_last_four: "4242", pix_qr_code: nil, pix_expires_at: nil)
    end

    it "maps provider statuses and treats unknown ones as pending" do
      { "in_process" => "pending", "rejected" => "rejected", "charged_back" => "charged_back", "mystery" => "pending" }.each do |provider_status, status|
        stub_mercado_pago_create(mercado_pago_payment("status" => provider_status))

        expect(gateway.create_card(payment, payer: payer, token: "t", payment_method_id: "visa", issuer_id: "1", installments: 1).status).to eq(status)
      end
    end

    it "raises GatewayRejected when the provider refuses the request" do
      stub_mercado_pago_create({ message: "invalid card token" }, status: 400)

      expect { gateway.create_card(payment, payer: payer, token: "bad", payment_method_id: "visa", issuer_id: nil, installments: 1) }
        .to raise_error(Payments::GatewayRejected)
    end
  end

  describe "#fetch" do
    it "reads the current state of a payment" do
      stub_mercado_pago_fetch(mercado_pago_payment("status" => "refunded"))

      expect(gateway.fetch("1234567").status).to eq("refunded")
    end

    it "raises GatewayUnavailable on server errors and network failures, logging only the error class" do
      stub_request(:get, "#{MercadoPagoHelpers::PAYMENTS_URL}/1").to_return(status: 500, body: "")
      expect { gateway.fetch("1") }.to raise_error(Payments::GatewayUnavailable)

      stub_request(:get, "#{MercadoPagoHelpers::PAYMENTS_URL}/2").to_timeout
      allow(Rails.logger).to receive(:warn)
      expect { gateway.fetch("2") }.to raise_error(Payments::GatewayUnavailable)
      expect(Rails.logger).to have_received(:warn).with({ message: "Mercado Pago request failed", error: "Net::OpenTimeout" })
    end
  end

  describe "#refund" do
    it "refunds with an idempotency key and returns the refreshed payment" do
      approved = create(:payment, :approved, provider_payment_id: "1234567")
      refund = stub_request(:post, "#{MercadoPagoHelpers::PAYMENTS_URL}/1234567/refunds")
        .with(headers: { "X-Idempotency-Key" => "#{approved.id}-refund" })
        .to_return(status: 201, body: { id: 1 }.to_json)
      stub_mercado_pago_fetch(mercado_pago_payment("status" => "refunded"))

      expect(gateway.refund(approved).status).to eq("refunded")
      expect(refund).to have_been_requested
    end
  end
end
