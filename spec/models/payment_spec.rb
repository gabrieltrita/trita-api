require "rails_helper"

RSpec.describe Payment do
  def result(overrides = {})
    Payments::GatewayResult.new(
      provider: "mercado_pago", provider_payment_id: "99", status: "approved", status_detail: "accredited", payment_method: "card",
      installments: 2, card_brand: "visa", card_last_four: "4242", pix_qr_code: nil, pix_qr_code_base64: nil, pix_ticket_url: nil, pix_expires_at: nil
    ).with(**overrides)
  end

  it "validates amount, currency, description and payment method" do
    payment = build(:payment, amount_cents: 0, currency: "USD", description: " ", payment_method: "boleto")

    expect(payment).not_to be_valid
    expect(payment.errors.attribute_names).to contain_exactly(:amount_cents, :currency, :description, :payment_method)
    expect(build(:payment, amount_cents: Payment::MAX_AMOUNT_CENTS + 1)).not_to be_valid
    expect(build(:payment, status: "paid")).not_to be_valid
  end

  it "squishes the description and audits the creation" do
    payment = create(:payment, description: "  Landing   page ")

    expect(payment.description).to eq("Landing page")
    expect(AuditLog.where(action: "payment.created", target_id: payment.id).sole.metadata).to eq("amount_cents" => 15_000, "currency" => "BRL")
  end

  it "is payable only when created or rejected and refundable only when approved" do
    expect(build(:payment).payable?).to be(true)
    expect(build(:payment, status: "rejected").payable?).to be(true)
    expect(build(:payment, status: "pending").payable?).to be(false)
    expect(build(:payment, status: "approved").refundable?).to be(true)
    expect(build(:payment, status: "pending").refundable?).to be(false)
  end

  describe "#apply!" do
    it "stores the gateway result, stamps approval and audits the status change" do
      payment = create(:payment)

      payment.apply!(result)

      expect(payment.reload).to have_attributes(status: "approved", provider_payment_id: "99", installments: 2, card_last_four: "4242")
      expect(payment.approved_at).to be_present
      expect(AuditLog.where(action: "payment.status_changed", target_id: payment.id).sole.metadata)
        .to eq("from" => "created", "to" => "approved", "payment_method" => "card")
    end

    it "stamps the refund and keeps the approval time" do
      payment = create(:payment, :approved, approved_at: 1.day.ago)

      expect { payment.apply!(result(status: "refunded")) }.not_to change(payment, :approved_at)
      expect(payment.refunded_at).to be_present
    end

    it "does not audit when the status stays the same" do
      payment = create(:payment, :pending_pix)

      expect { payment.apply!(result(status: "pending", payment_method: "pix")) }.not_to change(AuditLog.where(action: "payment.status_changed"), :count)
    end
  end

  it "finds pending payments that have not changed recently" do
    stale = travel_to(1.hour.ago) { create(:payment, :pending_pix) }
    create(:payment, :pending_pix)
    travel_to(1.hour.ago) { create(:payment, :approved) }

    expect(described_class.stale_pending).to eq([ stale ])
  end

  it "keeps the user from being destroyed while payments exist" do
    payment = create(:payment)

    expect { payment.user.destroy }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
