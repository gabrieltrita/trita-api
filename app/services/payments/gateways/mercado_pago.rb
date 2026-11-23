module Payments
  module Gateways
    class MercadoPago
      PROVIDER = "mercado_pago".freeze
      API_URI = URI("https://api.mercadopago.com")
      HTTP_TIMEOUT = 5
      PIX_EXPIRATION = 30.minutes
      REJECTED_STATUSES = [ 400, 422 ].freeze
      NETWORK_ERRORS = [ SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError, JSON::ParserError ].freeze
      STATUSES = {
        "pending" => "pending", "in_process" => "pending", "in_mediation" => "pending", "authorized" => "pending",
        "approved" => "approved", "rejected" => "rejected", "cancelled" => "cancelled",
        "refunded" => "refunded", "charged_back" => "charged_back"
      }.freeze

      def initialize(access_token:)
        @access_token = access_token
      end

      def create_pix(payment, payer:)
        body = charge_body(payment, payer).merge(payment_method_id: "pix", date_of_expiration: PIX_EXPIRATION.from_now.iso8601(3))
        result(post("/v1/payments", body, idempotency_key: idempotency_key(payment, "pix")))
      end

      def create_card(payment, payer:, token:, payment_method_id:, issuer_id:, installments:)
        body = charge_body(payment, payer).merge(token: token, payment_method_id: payment_method_id, issuer_id: issuer_id, installments: installments).compact
        result(post("/v1/payments", body, idempotency_key: idempotency_key(payment, "card")))
      end

      def fetch(provider_payment_id)
        result(request(Net::HTTP::Get.new("/v1/payments/#{provider_payment_id}")))
      end

      def refund(payment)
        post("/v1/payments/#{payment.provider_payment_id}/refunds", {}, idempotency_key: "#{payment.id}-refund")
        fetch(payment.provider_payment_id)
      end

      private

      def charge_body(payment, payer)
        identification = { type: "CPF", number: payer[:document] } if payer[:document].present?
        {
          transaction_amount: payment.amount_cents / 100.0,
          description: payment.description,
          external_reference: payment.id,
          payer: { email: payer[:email], identification: identification }.compact
        }
      end

      def idempotency_key(payment, payment_method)
        "#{payment.id}-#{payment_method}-#{payment.updated_at.to_f}"
      end

      def post(path, body, idempotency_key:)
        http_request = Net::HTTP::Post.new(path)
        http_request["X-Idempotency-Key"] = idempotency_key
        http_request.body = body.to_json
        request(http_request)
      end

      def request(http_request)
        http_request["Authorization"] = "Bearer #{@access_token}"
        http_request["Content-Type"] = "application/json"
        response = Net::HTTP.start(API_URI.host, API_URI.port, use_ssl: true, open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
          http.request(http_request)
        end
        return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)
        raise GatewayRejected if REJECTED_STATUSES.include?(response.code.to_i)

        raise GatewayUnavailable
      rescue *NETWORK_ERRORS => e
        Rails.logger.warn({ message: "Mercado Pago request failed", error: e.class.name })
        raise GatewayUnavailable
      end

      def result(json)
        pix = json["payment_method_id"] == "pix"
        transaction = json.dig("point_of_interaction", "transaction_data").to_h
        GatewayResult.new(
          provider: PROVIDER,
          provider_payment_id: json["id"].to_s,
          status: STATUSES.fetch(json["status"], "pending"),
          status_detail: json["status_detail"],
          payment_method: pix ? "pix" : "card",
          installments: json["installments"],
          card_brand: (json["payment_method_id"] unless pix),
          card_last_four: json.dig("card", "last_four_digits"),
          pix_qr_code: transaction["qr_code"],
          pix_qr_code_base64: transaction["qr_code_base64"],
          pix_ticket_url: transaction["ticket_url"],
          pix_expires_at: (json["date_of_expiration"] if pix)
        )
      end
    end
  end
end
