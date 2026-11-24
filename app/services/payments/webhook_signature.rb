module Payments
  class WebhookSignature
    SECRET_ENV = "MERCADO_PAGO_WEBHOOK_SECRET".freeze

    def self.valid?(header:, request_id:, data_id:)
      new(header, request_id, data_id).valid?
    end

    def initialize(header, request_id, data_id)
      @parts = header.to_s.split(",").filter_map { |part| part.strip.split("=", 2) if part.include?("=") }.to_h
      @request_id = request_id.to_s
      @data_id = data_id.to_s
    end

    def valid?
      return false if [ secret, @data_id, @parts["ts"], @parts["v1"] ].any?(&:blank?)

      ActiveSupport::SecurityUtils.secure_compare(OpenSSL::HMAC.hexdigest("SHA256", secret, manifest), @parts["v1"])
    end

    private

    def secret
      ENV.fetch(SECRET_ENV, "")
    end

    def manifest
      [ "id:#{@data_id.downcase}", ("request-id:#{@request_id}" if @request_id.present?), "ts:#{@parts['ts']}" ].compact.map { |part| "#{part};" }.join
    end
  end
end
