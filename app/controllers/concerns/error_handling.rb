module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_internal_error unless Rails.env.local?
    rescue_from ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActiveRecord::RecordInvalid, with: :handle_record_invalid
    rescue_from ActionController::ParameterMissing, with: :handle_bad_request
    rescue_from Pundit::NotAuthorizedError, with: :handle_forbidden
    rescue_from ActionDispatch::Http::Parameters::ParseError, with: :handle_bad_request
    rescue_from Auth::Unauthorized, with: :handle_unauthorized
    rescue_from Auth::ReauthenticationFailed, with: :handle_reauthentication_failed
    rescue_from Auth::ProviderUnavailable, with: :handle_provider_unavailable
    rescue_from Payments::GatewayUnavailable, with: :handle_payments_unavailable
    rescue_from Payments::GatewayRejected, with: :handle_payment_request_invalid
  end

  private

  def render_error(status:, code:, message:, details: nil)
    body = { error: { code: code, message: message } }
    body[:error][:details] = details if details.present?
    render json: body, status: status
  end

  def render_validation_errors(record)
    render_error(
      status: :unprocessable_content,
      code: "validation_failed",
      message: "Invalid data",
      details: validation_details(record.errors)
    )
  end

  def validation_details(errors)
    errors.group_by(&:attribute).transform_values do |list|
      list.map { |error| { code: validation_code(error), message: error.full_message } }
    end
  end

  def validation_code(error)
    error.options[:message].is_a?(Symbol) ? error.options[:message].to_s : error.type.to_s
  end

  def handle_not_found(_error)
    render_error(status: :not_found, code: "not_found", message: "Resource not found")
  end

  def handle_record_invalid(error)
    render_validation_errors(error.record)
  end

  def handle_bad_request(error)
    render_error(status: :bad_request, code: "bad_request", message: error.message)
  end

  def handle_forbidden(_error)
    render_error(status: :forbidden, code: "forbidden", message: "You are not allowed to perform this action")
  end

  def handle_unauthorized(error)
    render_error(status: :unauthorized, code: error.code, message: error.message)
  end

  def handle_reauthentication_failed(error)
    render_error(status: :unprocessable_content, code: error.code, message: error.message)
  end

  def handle_provider_unavailable(error)
    render_error(status: :service_unavailable, code: "oauth_provider_unavailable", message: error.message)
  end

  def handle_payments_unavailable(error)
    render_error(status: :service_unavailable, code: "payments_unavailable", message: error.message)
  end

  def handle_payment_request_invalid(error)
    render_error(status: :unprocessable_content, code: "payment_request_invalid", message: error.message)
  end

  def handle_internal_error(error)
    Rails.logger.error({ error: error.class.name, backtrace: Array(error.backtrace).first(10) })
    Sentry.capture_exception(error) if Sentry.initialized?
    render_error(status: :internal_server_error, code: "internal_error", message: "Internal server error")
  end
end
