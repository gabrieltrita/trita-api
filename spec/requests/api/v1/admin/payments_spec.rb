require "rails_helper"

RSpec.describe "Admin::Payments", :mercado_pago, type: :request do
  let(:admin) { create(:user, :admin) }
  let(:headers) { auth_headers(admin) }
  let(:user) { create(:user) }

  it "is admin only" do
    get "/api/v1/admin/payments", headers: auth_headers(user)
    expect(response).to have_http_status(:forbidden)
  end

  describe "GET /api/v1/admin/payments" do
    it "lists every payment with provider details and filters by status and user" do
      approved = create(:payment, :approved, user: user)
      create(:payment)

      get "/api/v1/admin/payments", params: { status: "approved", user_id: user.id }, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json["data"].map { |p| p["id"] }).to eq([ approved.id ])
      expect(json["data"].first).to include("user_id" => user.id, "provider" => "mercado_pago")

      get "/api/v1/admin/payments", headers: headers
      expect(json.dig("meta", "total")).to eq(2)
    end
  end

  describe "POST /api/v1/admin/payments" do
    it "creates a payment for a confirmed user, audited with the admin as actor" do
      post "/api/v1/admin/payments", params: { user_id: user.id, amount_cents: 250_000, description: "Backend MVP" }, headers: headers, as: :json

      expect(response).to have_http_status(:created)
      expect(json["data"]).to include("user_id" => user.id, "amount_cents" => 250_000, "status" => "created")
      expect(AuditLog.where(action: "payment.created").sole.actor).to eq(admin)
    end

    it "validates the amount and description" do
      post "/api/v1/admin/payments", params: { user_id: user.id, amount_cents: 0, description: "" }, headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(json.dig("error", "details").keys).to contain_exactly("amount_cents", "description")
    end

    it "does not charge unconfirmed or anonymized users" do
      post "/api/v1/admin/payments", params: { user_id: create(:user, :unconfirmed).id, amount_cents: 100, description: "x" }, headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/admin/payments/:id/refund" do
    it "refunds an approved payment and audits it" do
      payment = create(:payment, :approved, provider_payment_id: "1234567")
      stub_request(:post, "#{MercadoPagoHelpers::PAYMENTS_URL}/1234567/refunds").to_return(status: 201, body: "{}")
      stub_mercado_pago_fetch(mercado_pago_payment("status" => "refunded"))

      post "/api/v1/admin/payments/#{payment.id}/refund", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(json["data"]).to include("status" => "refunded")
      expect(json.dig("data", "refunded_at")).to be_present
      expect(AuditLog.where(action: "payment.refunded", target_id: payment.id)).to exist
    end

    it "refuses a payment that is not approved" do
      post "/api/v1/admin/payments/#{create(:payment).id}/refund", headers: headers, as: :json

      expect(response).to have_http_status(:conflict)
      expect(json.dig("error", "code")).to eq("payment_not_refundable")
    end

    it "answers 404 for an unknown payment and 503 when the provider is down" do
      post "/api/v1/admin/payments/#{SecureRandom.uuid}/refund", headers: headers, as: :json
      expect(response).to have_http_status(:not_found)

      payment = create(:payment, :approved, provider_payment_id: "55")
      stub_request(:post, "#{MercadoPagoHelpers::PAYMENTS_URL}/55/refunds").to_timeout
      post "/api/v1/admin/payments/#{payment.id}/refund", headers: headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
