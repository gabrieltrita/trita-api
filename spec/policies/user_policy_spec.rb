require "rails_helper"

RSpec.describe UserPolicy do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  describe "scope" do
    it "lets admins see every user" do
      user
      expect(described_class::Scope.new(admin, User).resolve).to contain_exactly(admin, user)
    end

    it "limits regular users to themselves" do
      admin
      expect(described_class::Scope.new(user, User).resolve).to contain_exactly(user)
    end
  end

  context "without a user" do
    subject(:policy) { described_class.new(nil, user) }

    it "grants nothing" do
      expect([ policy.index?, policy.show?, policy.update?, policy.destroy? ]).to all(be_falsey)
    end
  end
end
