require "rails_helper"

RSpec.describe Payments::WebhookSignature, :mercado_pago do
  def valid?(header, request_id: "req-1", data_id: "123")
    described_class.valid?(header: header, request_id: request_id, data_id: data_id)
  end

  it "accepts the HMAC of the documented manifest" do
    expect(valid?(mercado_pago_signature("123"))).to be(true)
  end

  it "lowercases alphanumeric ids and leaves the request id out when it is missing" do
    expect(valid?(mercado_pago_signature("ABC1"), data_id: "ABC1")).to be(true)
    expect(valid?(mercado_pago_signature("123", request_id: nil), request_id: nil)).to be(true)
  end

  it "rejects a wrong secret, a tampered id and malformed headers" do
    expect(valid?(mercado_pago_signature("123", secret: "other"))).to be(false)
    expect(valid?(mercado_pago_signature("123"), data_id: "124")).to be(false)
    expect(valid?("garbage")).to be(false)
    expect(valid?(nil)).to be(false)
    expect(valid?(mercado_pago_signature(""), data_id: "")).to be(false)
  end

  it "rejects everything when no secret is configured" do
    ENV["MERCADO_PAGO_WEBHOOK_SECRET"] = ""

    expect(valid?(mercado_pago_signature("123", secret: ""))).to be(false)
  end
end
