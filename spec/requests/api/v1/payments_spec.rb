require "rails_helper"

RSpec.describe "Payments", :mercado_pago, type: :request do
  let(:user) { create(:user, email: "client@example.com") }
  let(:headers) { auth_headers(user) }
  let(:payment) { create(:payment, user: user, amount_cents: 15_000) }

  it "requires authentication" do
    get "/api/v1/payments"
    expect(response).to have_http_status(:unauthorized)
  end

  describe "GET /api/v1/payments" do
    it "lists only the current user's payments" do
      payment
      create(:payment)

      get "/api/v1/payments", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["id"] }).to eq([ payment.id ])
      expect(json["data"].first).not_to have_key("provider_payment_id")
      expect(json.dig("meta", "total")).to eq(1)
    end
  end

  describe "GET /api/v1/payments/:id" do
    it "shows the payment and hides other users' payments" do
      get "/api/v1/payments/#{payment.id}", headers: headers
      expect(json.dig("data", "status")).to eq("created")

      get "/api/v1/payments/#{create(:payment).id}", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/payments/:id/pix" do
    it "creates the Pix charge, returns the QR code and audits the attempt" do
      stub = stub_mercado_pago_create(mercado_pago_pix).with { |request| JSON.parse(request.body).dig("payer", "identification", "number") == "12345678909" }

      post "/api/v1/payments/#{payment.id}/pix", params: { payer_document: "123.456.789-09" }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(stub).to have_been_requested
      expect(json["data"]).to include("status" => "pending", "payment_method" => "pix", "pix_qr_code" => "00020126pix")
      expect(payment.reload).to have_attributes(provider: "mercado_pago", provider_payment_id: "7654321")
      expect(AuditLog.where(action: "payment.attempted", target_id: payment.id).sole.metadata).to eq("payment_method" => "pix")
    end

    it "refuses a payment that is already pending" do
      pending = create(:payment, :pending_pix, user: user)

      post "/api/v1/payments/#{pending.id}/pix", headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("payment_not_payable")
    end

    it "hides other users' payments" do
      post "/api/v1/payments/#{create(:payment).id}/pix", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "answers 422 when the provider refuses the charge" do
      stub_mercado_pago_create({ message: "invalid payer" }, status: 400)

      post "/api/v1/payments/#{payment.id}/pix", headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("payment_request_invalid")
    end

    it "answers 503 when payments are not configured" do
      ENV.delete("MERCADO_PAGO_ACCESS_TOKEN")

      post "/api/v1/payments/#{payment.id}/pix", headers: headers, as: :json

      expect(response).to have_http_status(:service_unavailable)
      expect(json.dig("error", "code")).to eq("payments_unavailable")
      expect(payment.reload.status).to eq("created")
    end
  end

  describe "POST /api/v1/payments/:id/card" do
    let(:card_params) { { card_token: "tok_123", payment_method_id: "visa", issuer_id: "25", installments: 3 } }

    it "pays with the tokenized card, capping installments" do
      stub = stub_mercado_pago_create(mercado_pago_payment("installments" => 12)).with do |request|
        body = JSON.parse(request.body)
        body.slice("token", "issuer_id", "installments") == { "token" => "tok_123", "issuer_id" => "25", "installments" => 12 } && body["payer"] == { "email" => "client@example.com" }
      end

      post "/api/v1/payments/#{payment.id}/card", params: card_params.merge(installments: 40), headers: headers, as: :json

      expect(stub).to have_been_requested
      expect(json["data"]).to include("status" => "approved", "card_brand" => "visa", "card_last_four" => "4242", "installments" => 12)
      expect(json.dig("data", "approved_at")).to be_present
    end

    it "returns a rejection as data, so the card can be tried again" do
      stub_mercado_pago_create(mercado_pago_payment("status" => "rejected", "status_detail" => "cc_rejected_insufficient_amount"))

      post "/api/v1/payments/#{payment.id}/card", params: card_params, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("status" => "rejected", "status_detail" => "cc_rejected_insufficient_amount")
      expect(payment.reload.payable?).to be(true)
    end

    it "answers 422 when the provider refuses the request" do
      stub_mercado_pago_create({ message: "invalid token" }, status: 400)

      post "/api/v1/payments/#{payment.id}/card", params: card_params, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "code")).to eq("payment_request_invalid")
    end

    it "requires the card token" do
      post "/api/v1/payments/#{payment.id}/card", params: { payment_method_id: "visa" }, headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
    end

    it "hides other users' payments" do
      post "/api/v1/payments/#{create(:payment).id}/card", params: card_params, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an approved payment" do
      approved = create(:payment, :approved, user: user)

      post "/api/v1/payments/#{approved.id}/card", params: card_params, headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
    end

    it "answers 503 when the provider is unreachable" do
      stub_request(:post, MercadoPagoHelpers::PAYMENTS_URL).to_return(status: 502)

      post "/api/v1/payments/#{payment.id}/card", params: card_params, headers: headers, as: :json

      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
