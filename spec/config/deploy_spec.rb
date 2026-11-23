require "rails_helper"
require "kamal"

RSpec.describe "Kamal deploy configuration" do
  OPTIONAL_SECRETS = %w[SENTRY_DSN APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY MERCADO_PAGO_ACCESS_TOKEN MERCADO_PAGO_WEBHOOK_SECRET].freeze

  let(:app) { YAML.load_file(Rails.root.join("config/app.yml")).fetch("shared") }
  let(:raw) { Rails.root.join("config/deploy.yml").read }
  let(:environment) do
    {
      "KAMAL_REGISTRY_USERNAME" => "Octo",
      "DEPLOY_HOST" => "203.0.113.10",
      "APP_HOST" => "api.example.com",
      "CORS_ORIGINS" => "https://app.example.com",
      "FRONTEND_URL" => "https://app.example.com",
      "MAILER_FROM" => "App <no-reply@example.com>",
      "SMTP_ADDRESS" => "smtp.example.com"
    }
  end
  let(:config) { render("config/deploy.yml") }
  let(:staging) { config.deep_merge(render("config/deploy.staging.yml")) }
  let(:secret_names) do
    config.dig("env", "secret") +
      config["accessories"].values.flat_map { |accessory| accessory.dig("env", "secret").to_a } +
      config.dig("registry", "password")
  end

  def with_env(vars)
    originals = vars.keys.index_with { |key| ENV[key] }
    vars.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    originals.each { |key, value| value ? ENV[key] = value : ENV.delete(key) }
  end

  def render(file)
    with_env(environment) do
      Dir.chdir(Rails.root) { YAML.safe_load(ERB.new(Rails.root.join(file).read).result) }
    end
  end

  def expanded_secrets(destination, vars)
    unset = OPTIONAL_SECRETS.flat_map { |name| [ name, "STAGING_#{name}" ] }.index_with { nil }
    with_env(unset.merge(vars)) { Dir.chdir(Rails.root) { Kamal::Secrets.new(destination: destination).to_h } }
  end

  def secrets_lines(file)
    Rails.root.join(file).read.lines.map(&:strip).reject(&:empty?)
  end

  it "names the service and the image after config/app.yml and nothing else" do
    expect(config["service"]).to eq("#{app['slug']}-api")
    expect(config["image"]).to eq("octo/#{app['slug']}-api")
    [ app["name"], app["slug"], app["domain"] ].each do |identity|
      expect(raw).not_to include(identity)
      expect(Rails.root.join("config/deploy.staging.yml").read).not_to include(identity)
    end
  end

  it "delivers every variable the app requires to boot in production" do
    delivered = config.dig("env", "clear").keys + config.dig("env", "secret")
    expect(EnvValidator::REQUIRED - delivered).to be_empty
  end

  it "runs Sidekiq as its own role and publishes no database or Redis port" do
    expect(config.dig("servers", "job", "cmd")).to eq("bundle exec sidekiq -C config/sidekiq.yml")
    expect(config["accessories"].values.map { |accessory| accessory["port"] }).to all(be_nil)
  end

  it "serializes empty optional values as strings" do
    expect(config.dig("env", "clear", "GOOGLE_CLIENT_IDS")).to eq("")
  end

  describe ".kamal/secrets" do
    let(:vars) { secret_names.index_with { |name| "prod-#{name}" } }

    it "only references environment variables, one for each secret" do
      lines = secrets_lines(".kamal/secrets")

      expect(lines.map { |line| line.split("=").first }).to match_array(secret_names)
      expect(lines).to all(match(/\A([A-Z_]+)=\$\1\z/))
    end

    it "expands to the exported values and to empty strings for the optional ones left out" do
      values = expanded_secrets(nil, vars.except(*OPTIONAL_SECRETS))

      expect(values.keys).to match_array(secret_names)
      expect(values.slice(*OPTIONAL_SECRETS).values).to all(eq(""))
      expect(values.except(*OPTIONAL_SECRETS)).to eq(vars.except(*OPTIONAL_SECRETS))
    end

    it "passes an optional value through unchanged" do
      values = expanded_secrets(nil, vars.merge("SENTRY_DSN" => "https://dsn.example/1", "APPLE_PRIVATE_KEY" => "-----BEGIN-----\\nabc"))

      expect(values["SENTRY_DSN"]).to eq("https://dsn.example/1")
      expect(values["APPLE_PRIVATE_KEY"]).to eq("-----BEGIN-----\\nabc")
      expect(values.values.grep(/:-\}/)).to be_empty
    end
  end

  describe "staging" do
    let(:staging_vars) { secret_names.without("KAMAL_REGISTRY_PASSWORD").index_with { |name| "staging-#{name}" }.transform_keys { |name| "STAGING_#{name}" } }
    let(:production_vars) { secret_names.index_with { |name| "prod-#{name}" } }

    it "runs as its own service with its own database and the API docs on" do
      expect(staging["service"]).to eq("#{app['slug']}-api-staging")
      expect(staging.dig("accessories", "db", "env", "clear", "POSTGRES_DB")).to eq("#{app['slug']}_api_staging")
      expect(staging.dig("accessories", "db", "image")).to eq(config.dig("accessories", "db", "image"))
      expect(staging.dig("env", "clear", "ENABLE_API_DOCS")).to eq("true")
      expect(config.dig("env", "clear")).not_to have_key("ENABLE_API_DOCS")
      expect(staging["service"]).not_to eq(config["service"])
    end

    it "keeps the same secrets and the same boot requirements as production" do
      expect(staging.dig("env", "secret")).to eq(config.dig("env", "secret"))
      expect(EnvValidator::REQUIRED - (staging.dig("env", "clear").keys + staging.dig("env", "secret"))).to be_empty
    end

    it "only references STAGING_ variables, except the shared registry token" do
      lines = secrets_lines(".kamal/secrets.staging")

      expect(lines.map { |line| line.split("=").first }).to match_array(secret_names)
      shared, own = lines.partition { |line| line.start_with?("KAMAL_REGISTRY_PASSWORD=") }
      expect(shared).to eq([ "KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD" ])
      expect(own).to all(match(/\A([A-Z_]+)=\$STAGING_\1\z/))
    end

    it "never expands to a production value" do
      staging_required = staging_vars.except(*OPTIONAL_SECRETS.map { |name| "STAGING_#{name}" })
      values = expanded_secrets("staging", production_vars.merge(staging_required))

      expect(values.except("KAMAL_REGISTRY_PASSWORD").values.grep(/prod-/)).to be_empty
      expect(values["JWT_SECRET"]).to eq("staging-JWT_SECRET")
      expect(values["KAMAL_REGISTRY_PASSWORD"]).to eq("prod-KAMAL_REGISTRY_PASSWORD")
      expect(values.slice(*OPTIONAL_SECRETS).values).to all(eq(""))
    end

    it "passes the staging optional values through" do
      values = expanded_secrets("staging", production_vars.merge(staging_vars))

      expect(values["SENTRY_DSN"]).to eq("staging-SENTRY_DSN")
    end
  end
end
