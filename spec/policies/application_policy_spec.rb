require "rails_helper"

RSpec.describe ApplicationPolicy do
  let(:policy) { described_class.new(create(:user, :admin), Object.new) }

  it "denies every action by default, even to admins" do
    expect([ policy.index?, policy.show?, policy.create?, policy.update?, policy.destroy? ]).to all(be(false))
  end

  it "forces each policy scope to define resolve" do
    expect { described_class::Scope.new(nil, User).resolve }.to raise_error(NoMethodError, /Define #resolve in ApplicationPolicy::Scope/)
  end
end
