module Api
  module V1
    module Auth
      class OauthController < ApplicationController
        skip_before_action :authenticate_user!

        def google
          sign_in_with("google")
        end

        def apple
          sign_in_with("apple")
        end

        private

        def sign_in_with(provider)
          claims = with_client_names(::Auth::Oauth::Providers.verify(provider, params.require(:id_token)))
          user = ::Auth::OauthSignin.call(provider: provider, claims: claims, consents: consents)
          sign_in_or_challenge(user, provider: provider)
        rescue ::Auth::OauthSignin::ConsentRequired => e
          render_error(status: :unprocessable_content, code: "validation_failed", message: "Invalid data", details: consent_details(e.kinds))
        end

        def with_client_names(claims)
          names = params.permit(:first_name, :last_name)
          claims.with(
            given_name: claims.given_name.presence || names[:first_name].presence,
            family_name: claims.family_name.presence || names[:last_name].presence
          )
        end

        def consents
          Consent::KINDS.keys.index_with { |kind| truthy?(params[:"accept_#{kind}"]) }
        end

        def consent_details(kinds)
          kinds.index_by { |kind| :"accept_#{kind}" }.transform_values do |kind|
            [ { code: "required", message: I18n.t("consents.required", kind: I18n.t("consents.kinds.#{kind}")) } ]
          end
        end
      end
    end
  end
end
