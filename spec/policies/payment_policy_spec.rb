require "rails_helper"

RSpec.describe PaymentPolicy do
  let(:owner) { create(:user) }
  let(:other) { create(:user) }
  let(:admin) { create(:user, :admin) }
  let(:payment) { create(:payment, user: owner) }

  it "lets the owner see and pay a payment, and nobody else" do
    %i[show? pix? card?].each do |action|
      expect(described_class.new(owner, payment).public_send(action)).to be(true)
      expect(described_class.new(other, payment).public_send(action)).to be(false)
    end
    expect(described_class.new(other, Payment).index?).to be(true)
  end

  it "lets only admins manage payments" do
    expect(described_class.new(admin, Payment).manage?).to be(true)
    expect(described_class.new(owner, Payment).manage?).to be(false)
  end

  it "scopes to the user's own payments" do
    payment
    create(:payment, user: other)

    expect(described_class::Scope.new(owner, Payment).resolve).to eq([ payment ])
  end
end
