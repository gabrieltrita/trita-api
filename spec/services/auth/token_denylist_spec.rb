require "rails_helper"

RSpec.describe Auth::TokenDenylist do
  it "denies a token until it expires" do
    described_class.add("live-jti", 5.minutes.from_now.to_i)
    expect(described_class).to include("live-jti")
  end

  it "skips tokens that already expired" do
    described_class.add("dead-jti", 1.second.ago.to_i)
    expect(described_class).not_to include("dead-jti")
  end
end
