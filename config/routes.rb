require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "health" => "health#show", as: :health_check

  mount Sidekiq::Web => "/sidekiq"

  if Rails.env.local? || ENV["ENABLE_API_DOCS"] == "true"
    get "docs" => "docs#index"
    get "docs/openapi.yaml" => "docs#spec", as: :openapi_spec
  end

  namespace :api, defaults: { format: :json } do
    namespace :v1 do
      scope :auth, module: :auth, as: :auth do
        post   "register",        to: "registrations#create"
        post   "login",           to: "sessions#create"
        post   "two_factor",      to: "two_factor#create"
        delete "logout",          to: "sessions#destroy"
        post   "refresh",         to: "tokens#create"
        post   "confirm",         to: "confirmations#create"
        post   "confirm/resend",  to: "confirmations#resend"
        post   "email/confirm",   to: "confirmations#email_change"
        post   "password/forgot", to: "passwords#forgot"
        post   "password/reset",  to: "passwords#reset"
        post   "oauth/google",    to: "oauth#google"
        post   "oauth/apple",     to: "oauth#apple"
      end

      resource :me, only: %i[show update destroy], controller: :me do
        patch :password, action: :update_password
        patch :email, action: :update_email
        get :export

        scope module: :me do
          resources :sessions, only: %i[index destroy]
          resources :consents, only: %i[index create]
          resources :identities, only: %i[index create destroy]
          resource :two_factor, only: %i[show destroy], controller: :two_factor do
            post :setup
            post :enable
            post :backup_codes
          end
        end
      end

      resources :roles, only: :index

      resources :payments, only: %i[index show] do
        member do
          post :pix
          post :card
        end
      end

      scope :webhooks, module: :webhooks, as: :webhooks do
        post "mercado_pago", to: "mercado_pago#create"
      end

      namespace :admin do
        resources :users do
          member do
            post :unlock
            post :deactivate
            post :reactivate
            delete :two_factor, action: :reset_two_factor
          end
        end
        resources :audit_logs, only: :index
        resources :payments, only: %i[index create] do
          post :refund, on: :member
        end
      end

      draw :app
    end
  end
end
