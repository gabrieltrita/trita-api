require "rails_helper"

RSpec.describe "Mercado Pago webhook", :mercado_pago, type: :request do
  let(:payment) { create(:payment, :pending_pix, provider_payment_id: "7654321") }

  def notify(data_id, signature: mercado_pago_signature(data_id))
    post "/api/v1/webhooks/mercado_pago", params: { type: "payment", action: "payment.updated", data: { id: data_id } },
                                          headers: { "x-signature" => signature, "x-request-id" => "req-1" }, as: :json
  end

  it "enqueues a sync for a known payment without trusting the body" do
    expect { notify(payment.provider_payment_id) }.to have_enqueued_job(PaymentSyncJob).with(payment)

    expect(response).to have_http_status(:ok)
    expect(payment.reload.status).to eq("pending")
  end

  it "acknowledges unknown ids and does nothing" do
    expect { notify("999") }.not_to have_enqueued_job(PaymentSyncJob)

    expect(response).to have_http_status(:ok)
  end

  it "rejects an invalid signature" do
    expect { notify(payment.provider_payment_id, signature: "ts=1,v1=bad") }.not_to have_enqueued_job(PaymentSyncJob)

    expect(response).to have_http_status(:unauthorized)
    expect(json.dig("error", "code")).to eq("webhook_signature_invalid")
  end
end
