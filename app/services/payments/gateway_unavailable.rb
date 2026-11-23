module Payments
  class GatewayUnavailable < StandardError
    def initialize(message = "Payments are unavailable. Try again shortly.")
      super
    end
  end
end
