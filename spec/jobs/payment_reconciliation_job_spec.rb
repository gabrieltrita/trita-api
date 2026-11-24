require "rails_helper"

RSpec.describe PaymentReconciliationJob do
  it "enqueues a sync for every stale pending payment", :mercado_pago do
    stale = travel_to(1.hour.ago) { create(:payment, :pending_pix) }
    create(:payment, :pending_pix)

    expect { described_class.perform_now }.to have_enqueued_job(PaymentSyncJob).with(stale).exactly(:once)
  end

  it "does nothing when payments are not configured" do
    ENV.delete("MERCADO_PAGO_ACCESS_TOKEN")
    travel_to(1.hour.ago) { create(:payment, :pending_pix) }

    expect { described_class.perform_now }.not_to have_enqueued_job(PaymentSyncJob)
  end

  it "is scheduled in sidekiq-cron" do
    schedule = YAML.load_file(Rails.root.join("config/schedule.yml"))
    expect(schedule.dig("payment_reconciliation", "class")).to eq("PaymentReconciliationJob")
  end
end
