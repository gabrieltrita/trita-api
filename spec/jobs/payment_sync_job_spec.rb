require "rails_helper"

RSpec.describe PaymentSyncJob, :mercado_pago do
  it "applies the provider's current state" do
    payment = create(:payment, :pending_pix, provider_payment_id: "7654321")
    stub_mercado_pago_fetch(mercado_pago_pix("status" => "approved", "status_detail" => "accredited"))

    described_class.perform_now(payment)

    expect(payment.reload).to have_attributes(status: "approved", status_detail: "accredited")
    expect(payment.approved_at).to be_present
  end

  it "retries later when the provider is unavailable" do
    payment = create(:payment, :pending_pix, provider_payment_id: "1")
    stub_request(:get, "#{MercadoPagoHelpers::PAYMENTS_URL}/1").to_return(status: 503)

    expect { described_class.perform_now(payment) }.to have_enqueued_job(described_class)
    expect(payment.reload.status).to eq("pending")
  end
end
