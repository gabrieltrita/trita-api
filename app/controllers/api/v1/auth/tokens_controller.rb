module Api
  module V1
    module Auth
      class TokensController < ApplicationController
        skip_before_action :authenticate_user!

        def create
          raw = refresh_token_from_request
          if raw.blank?
            raise ::Auth::Unauthorized.new("Missing refresh token", code: "missing_token") if cookie_transport?

            raise ActionController::ParameterMissing, :refresh_token
          end

          user, tokens = ::Auth::RefreshTokenRotator.call(raw, request: request)
          render_session(user, tokens)
        rescue ::Auth::Unauthorized
          clear_refresh_cookie
          raise
        end
      end
    end
  end
end
