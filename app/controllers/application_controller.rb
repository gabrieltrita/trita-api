class ApplicationController < ActionController::API
  include ActionController::Cookies
  include Pundit::Authorization
  include Pagy::Method
  include ErrorHandling
  include Authenticatable
  include TokenResponder

  wrap_parameters false

  prepend_before_action :set_current_request

  private

  def set_current_request
    Current.ip_address = request.remote_ip
    Current.user_agent = request.user_agent
    Current.request_id = request.request_id
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value) == true
  end

  def require_current_password!
    return if current_user.authenticate(params.require(:current_password).to_s)

    raise Auth::ReauthenticationFailed.new("Current password is incorrect", code: "invalid_current_password")
  end

  def require_second_factor!
    return unless current_user.two_factor_enabled?
    return if current_user.verify_second_factor(params[:code])

    raise Auth::ReauthenticationFailed.new("Invalid verification code", code: "invalid_two_factor_code")
  end
end
