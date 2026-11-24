require "rails_helper"

RSpec.describe EnvValidator do
  let(:valid_env) do
    {
      "DATABASE_URL" => "postgres://u:p@db/app",
      "REDIS_URL" => "redis://:p@redis:6379/1",
      "SIDEKIQ_REDIS_URL" => "redis://:p@redis:6379/0",
      "SECRET_KEY_BASE" => "f" * 64,
      "JWT_SECRET" => "a" * 64,
      "AR_ENCRYPTION_PRIMARY_KEY" => "b" * 32,
      "AR_ENCRYPTION_DETERMINISTIC_KEY" => "c" * 32,
      "AR_ENCRYPTION_KEY_DERIVATION_SALT" => "d" * 32,
      "APP_HOSTS" => "api.example.com",
      "CORS_ORIGINS" => "https://app.example.com",
      "FRONTEND_URL" => "https://app.example.com",
      "MAILER_FROM" => "App <no-reply@example.com>",
      "SMTP_ADDRESS" => "smtp.example.com",
      "SIDEKIQ_WEB_USERNAME" => "admin",
      "SIDEKIQ_WEB_PASSWORD" => "e" * 16
    }
  end

  it "accepts a complete configuration" do
    expect { described_class.validate!(valid_env) }.not_to raise_error
  end

  it "accepts a key list for rotation (old,new)" do
    expect(described_class.new(valid_env.merge("AR_ENCRYPTION_PRIMARY_KEY" => "#{'x' * 32},#{'y' * 32}")).errors).to be_empty
  end

  it "rejects a missing required variable" do
    expect { described_class.validate!(valid_env.except("JWT_SECRET")) }.to raise_error(/JWT_SECRET is not set/)
  end

  {
    "SECRET_KEY_BASE" => [ "curto", /SECRET_KEY_BASE must be at least 64/ ],
    "JWT_SECRET" => [ "curto", /JWT_SECRET must be at least 64/ ],
    "AR_ENCRYPTION_PRIMARY_KEY" => [ "#{'x' * 32},curta", /AR_ENCRYPTION_PRIMARY_KEY must be at least 32/ ],
    "SIDEKIQ_WEB_PASSWORD" => [ "123", /SIDEKIQ_WEB_PASSWORD must be at least 16/ ],
    "CORS_ORIGINS" => [ "*", /must not contain \*/ ]
  }.each do |key, (value, message)|
    it "rejects a weak or insecure #{key}" do
      expect(described_class.new(valid_env.merge(key => value)).errors.join("\n")).to match(message)
    end
  end

  it "requires https CORS origins" do
    expect(described_class.new(valid_env.merge("CORS_ORIGINS" => "http://app.example.com")).errors.join).to match(/https/)
  end

  it "reports a missing encryption key only as not set" do
    errors = described_class.new(valid_env.except("AR_ENCRYPTION_PRIMARY_KEY")).errors
    expect(errors).to eq([ "AR_ENCRYPTION_PRIMARY_KEY is not set" ])
  end

  describe "Sign in with Apple key" do
    let(:apple_env) { { "APPLE_TEAM_ID" => "TEAM123456", "APPLE_KEY_ID" => "KEY1234567", "APPLE_PRIVATE_KEY" => "pem" } }

    it "accepts none or all of the variables" do
      expect(described_class.new(valid_env).errors).to be_empty
      expect(described_class.new(valid_env.merge(apple_env)).errors).to be_empty
    end

    it "rejects a partial configuration" do
      errors = described_class.new(valid_env.merge(apple_env.except("APPLE_KEY_ID", "APPLE_PRIVATE_KEY"))).errors
      expect(errors).to eq([ "APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_PRIVATE_KEY must be set together (missing: APPLE_KEY_ID, APPLE_PRIVATE_KEY)" ])
    end
  end
end
