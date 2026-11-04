module TokenResponder
  extend ActiveSupport::Concern

  REFRESH_COOKIE = "#{Rails.configuration.x.app.slug}_refresh".freeze
  REFRESH_COOKIE_PATH = "/api/v1/auth".freeze

  private

  def cookie_transport?
    request.headers["X-Token-Transport"].to_s.casecmp?("cookie")
  end

  def render_session(user, tokens, status: :ok)
    tokens = tokens.dup
    if cookie_transport?
      write_refresh_cookie(tokens.delete(:refresh_token))
      tokens[:refresh_token_transport] = "cookie"
    end

    render json: {
      data: {
        user: UserBlueprint.render_as_hash(user),
        tokens: tokens,
        two_factor_setup_required: user.two_factor_setup_required?
      }
    }, status: status
  end

  def sign_in_or_challenge(user, provider: nil)
    refuse_deactivated!(user)
    return sign_in_and_render(user, provider: provider) unless user.two_factor_enabled?

    user.reset_failed_logins!
    render json: {
      data: { two_factor_required: true, challenge_token: Auth::TwoFactorChallenge.issue(user), expires_in: Auth::TwoFactorChallenge::TTL.to_i }
    }
  end

  def sign_in_and_render(user, two_factor: false, provider: nil)
    refuse_deactivated!(user)
    user.reset_failed_logins!
    user.track_sign_in!
    Current.user = user
    metadata = { two_factor: two_factor }
    metadata[:provider] = provider if provider
    AuditLog.record!("auth.login", target: user, actor: user, metadata: metadata)
    render_session(user, Auth::TokenIssuer.call(user, request: request))
  end

  def refuse_deactivated!(user)
    return unless user.deactivated?

    AuditLog.record!("auth.login_blocked", target: user, actor: nil)
    raise Auth::InvalidCredentials
  end

  def refresh_token_from_request
    params[:refresh_token].presence || (cookie_transport? ? cookies[REFRESH_COOKIE].presence : nil)
  end

  def write_refresh_cookie(value)
    cookies[REFRESH_COOKIE] = {
      value: value,
      httponly: true,
      secure: Rails.env.production?,
      same_site: :strict,
      path: REFRESH_COOKIE_PATH,
      expires: Auth::JsonWebToken.refresh_ttl.from_now
    }
  end

  def clear_refresh_cookie
    cookies.delete(REFRESH_COOKIE, path: REFRESH_COOKIE_PATH)
  end
end
