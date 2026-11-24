module Payments
  class GatewayRejected < StandardError
    def initialize(message = "The payment provider rejected the request")
      super
    end
  end
end
