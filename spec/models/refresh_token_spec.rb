require "rails_helper"

RSpec.describe RefreshToken do
  let(:user) { create(:user) }

  it "finds nothing for a blank token" do
    tokens_for(user)
    expect(described_class.find_by_raw_token("")).to be_nil
    expect(described_class.find_by_raw_token(nil)).to be_nil
  end

  it "keeps the first revocation reason" do
    token = described_class.find_by_raw_token(tokens_for(user)[:refresh_token])
    token.revoke!(reason: "logout")

    expect { token.revoke!(reason: described_class::ROTATED) }.not_to change { token.reload.revoked_at }
    expect(token.revoked_reason).to eq("logout")
  end
end
