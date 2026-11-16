source "https://rubygems.org"

gem "rails", "~> 8.1.1"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "bcrypt", "~> 3.1.7"
gem "jwt", "~> 3.3"

gem "rotp", "~> 6.4"

gem "pundit", "~> 2.4"

gem "rack-cors"

gem "rack-attack"

gem "redis", "~> 6.0"
gem "sidekiq", "~> 8.1"
gem "sidekiq-cron", "~> 2.0"
gem "connection_pool", "~> 3.0"

gem "sentry-ruby", "~> 7.2"
gem "sentry-rails", "~> 7.1"
gem "sentry-sidekiq", "~> 7.1"

gem "pagy", "~> 43.8"

gem "blueprinter", "~> 1.1"

gem "lograge", "~> 0.15"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false

  gem "dotenv-rails"
  gem "rspec-rails", "~> 8.1"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  gem "kamal", "~> 2.12", require: false
end

group :test do
  gem "shoulda-matchers", "~> 8.0"
  gem "simplecov", require: false
  gem "openapi_first", "~> 4.4", require: false
  gem "webmock", "~> 3.34", require: false
end
