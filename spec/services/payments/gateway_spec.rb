require "rails_helper"

RSpec.describe Payments::Gateway do
  it "is disabled and unavailable without an access token" do
    ENV.delete("MERCADO_PAGO_ACCESS_TOKEN")

    expect(described_class.enabled?).to be(false)
    expect { described_class.current }.to raise_error(Payments::GatewayUnavailable)
  end

  it "returns the Mercado Pago gateway when configured", :mercado_pago do
    expect(described_class.enabled?).to be(true)
    expect(described_class.current).to be_a(Payments::Gateways::MercadoPago)
  end
end
