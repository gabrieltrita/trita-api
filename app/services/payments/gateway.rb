module Payments
  module Gateway
    ACCESS_TOKEN_ENV = "MERCADO_PAGO_ACCESS_TOKEN".freeze

    def self.enabled?
      ENV[ACCESS_TOKEN_ENV].present?
    end

    def self.current
      raise GatewayUnavailable unless enabled?

      Gateways::MercadoPago.new(access_token: ENV.fetch(ACCESS_TOKEN_ENV))
    end
  end
end
