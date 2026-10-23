module Api
  module V1
    class MeController < ApplicationController
      def show
        render json: { data: UserBlueprint.render_as_hash(current_user, view: :self) }
      end

      def update
        if current_user.update(profile_params)
          AuditLog.record!("user.updated", target: current_user, metadata: { fields: current_user.saved_changes.keys - %w[updated_at] })
          render json: { data: UserBlueprint.render_as_hash(current_user, view: :self) }
        else
          render_validation_errors(current_user)
        end
      end

      def update_password
        require_current_password!

        if current_user.update(password: params.require(:password), password_confirmation: params[:password_confirmation])
          render_session(current_user, ::Auth::TokenIssuer.call(current_user, request: request))
        else
          render_validation_errors(current_user)
        end
      end

      def update_email
        require_current_password!
        new_email = params.require(:email).to_s.strip.downcase

        if new_email == current_user.email
          return render_error(status: :unprocessable_content, code: "validation_failed", message: "Invalid data",
                              details: { email: [ { code: "same_as_current", message: "Email is the same as the current one" } ] })
        end

        current_user.unconfirmed_email = new_email
        return render_validation_errors(current_user) unless current_user.valid?

        unless User.exists?(email: new_email)
          current_user.save!
          UserMailer.email_change_confirmation(current_user).deliver_later
          UserMailer.email_change_requested(current_user).deliver_later
          AuditLog.record!("user.email_change_requested", target: current_user)
        end

        render json: { data: { message: "A confirmation link was sent to the new email." } }, status: :accepted
      end

      def destroy
        require_current_password!
        require_second_factor!

        current_user.anonymize!
        ::Auth::TokenDenylist.add(current_token_payload["jti"], current_token_payload["exp"])
        AuditLog.record!("user.anonymized", target: current_user, metadata: { by: "self" })
        clear_refresh_cookie
        head :no_content
      end

      def export
        AuditLog.record!("user.data_exported", target: current_user)
        response.headers["Content-Disposition"] = %(attachment; filename="#{Rails.configuration.x.app.slug}-data-#{Date.current.iso8601}.json")
        render json: UserDataExport.new(current_user).as_json
      end

      private

      def profile_params
        params.permit(:first_name, :last_name, :phone)
      end
    end
  end
end
