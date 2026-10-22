source "https://rubygems.org"

gem "rails", "~> 8.1.1"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[ windows jruby ]

gem "bcrypt", "~> 3.1.7"
gem "jwt", "~> 2.9"

gem "rotp", "~> 6.3"

gem "pundit", "~> 2.4"

gem "rack-cors"

gem "rack-attack"

gem "redis", "~> 5.3"
gem "sidekiq", "~> 7.3"
gem "sidekiq-cron", "~> 2.0"
gem "connection_pool", "~> 2.5"

gem "sentry-ruby", "~> 7.1"
gem "sentry-rails", "~> 7.1"
gem "sentry-sidekiq", "~> 7.1"

gem "pagy", "~> 9.3"

gem "blueprinter", "~> 1.1"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"
  gem "bundler-audit", require: false
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false

  gem "dotenv-rails"
  gem "rspec-rails", "~> 8.0"
  gem "factory_bot_rails"
  gem "faker"
end

group :test do
  gem "shoulda-matchers", "~> 6.4"
end
