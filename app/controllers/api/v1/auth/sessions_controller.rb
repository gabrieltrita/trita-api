module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        skip_before_action :authenticate_user!, only: :create

        def create
          email = params.require(:email).to_s
          user = User.authenticate_by(email: email, password: params.require(:password).to_s)
          candidate = user || User.find_by(email: email)

          if candidate&.access_locked? || candidate&.deactivated?
            AuditLog.record!("auth.login_blocked", target: candidate, actor: nil)
            raise ::Auth::InvalidCredentials
          end

          if user.nil?
            candidate&.register_failed_login!
            AuditLog.record!("auth.login_failed", target: candidate, actor: nil)
            raise ::Auth::InvalidCredentials
          end

          unless user.confirmed?
            return render_error(status: :forbidden, code: "email_not_confirmed",
                                message: "Confirm your email before logging in. You can request a new link.")
          end

          sign_in_or_challenge(user)
        end

        def destroy
          ::Auth::TokenDenylist.add(current_token_payload["jti"], current_token_payload["exp"])

          if truthy?(params[:all_devices])
            current_user.revoke_all_sessions!
          elsif current_session_id
            current_user.revoke_session!(current_session_id)
          end

          clear_refresh_cookie
          AuditLog.record!("auth.logout", target: current_user, metadata: { all_devices: truthy?(params[:all_devices]) })
          head :no_content
        end
      end
    end
  end
end
