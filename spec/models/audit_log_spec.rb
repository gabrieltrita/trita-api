require "rails_helper"

RSpec.describe AuditLog do
  let(:user) { create(:user) }

  it "stores the request user agent truncated to 500 characters" do
    Current.user_agent = "A" * 600
    log = described_class.record!("auth.login", target: user, actor: user)
    expect(log.user_agent.length).to eq(500)
  end

  context "when the record cannot be saved" do
    before { allow(described_class).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, "database is down") }

    it "never breaks the request and logs the failure" do
      allow(Rails.logger).to receive(:error)
      expect(described_class.record!("auth.login", target: user)).to be_nil
      expect(Rails.logger).to have_received(:error).with(/failed to record auth.login: ActiveRecord::StatementInvalid/)
    end

    it "reports the failure to Sentry when enabled" do
      with_sentry do |transport|
        described_class.record!("auth.login", target: user)
        expect(transport.events.map { |e| e.exception.values.last.type }).to eq([ "ActiveRecord::StatementInvalid" ])
      end
    end
  end
end
