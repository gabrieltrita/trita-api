require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

module TritaApi
  class Application < Rails::Application
    config.load_defaults 8.1

    config.autoload_lib(ignore: %w[assets tasks])

    config.api_only = true

    config.x.app = config_for(:app)

    config.middleware.use ActionDispatch::Cookies

    config.time_zone = "America/Sao_Paulo"
    config.i18n.default_locale = :en
    config.i18n.available_locales = [ :en ]

    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
      g.test_framework :rspec
      g.factory_bot dir: "spec/factories"
    end

    config.active_job.queue_adapter = :sidekiq
    config.action_mailer.deliver_later_queue_name = :mailers

    config.active_record.encryption.primary_key = ENV["AR_ENCRYPTION_PRIMARY_KEY"]&.split(",")&.map(&:strip)
    config.active_record.encryption.deterministic_key = ENV["AR_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["AR_ENCRYPTION_KEY_DERIVATION_SALT"]
    config.active_record.encryption.support_unencrypted_data = false
    config.active_record.encryption.encrypt_fixtures = true
    config.active_record.encryption.store_key_references = true
  end
end
