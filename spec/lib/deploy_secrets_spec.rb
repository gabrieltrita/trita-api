require "rails_helper"
require "deploy_secrets"

RSpec.describe DeploySecrets do
  let(:slug) { Rails.configuration.x.app.slug }
  let(:host_key) { "203.0.113.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFakeHostKeyForSpecsOnly\n" }
  let(:runner) { DeploySecretsFakeRunner.new(host_key: host_key) }

  class DeploySecretsFakeRunner
    Status = Struct.new(:ok) do
      def success? = ok
    end

    attr_reader :stored, :commands
    attr_accessor :existing, :failing

    def initialize(host_key:)
      @host_key = host_key
      @stored = {}
      @commands = []
      @existing = []
      @failing = nil
    end

    def capture3(*command, stdin_data:)
      @commands << command
      return [ "", "boom\n", Status.new(false) ] if command.first == failing

      case command
      in [ "ssh-keygen", "-q", *, "-f", path ]
        File.write(path, "PRIVATE KEY\n")
        File.write("#{path}.pub", "ssh-ed25519 AAAAPUBLIC #{command[command.index("-C") + 1]}\n")
        ok
      in [ "ssh-keygen", "-l", "-f", path ]
        ok("256 SHA256:fingerprint #{File.read(path).split.first} (ED25519)\n")
      in [ "ssh-keyscan", *, host ]
        ok(@host_key)
      in [ "gh", "secret", "list", * ]
        ok(existing.map { |name| "#{name}\n" }.join)
      in [ "gh", "secret", "set", name, * ]
        @stored[name] = stdin_data
        ok
      end
    end

    private

    def ok(output = "")
      [ output, "", Status.new(true) ]
    end
  end

  def secrets(environment: "staging", host: "203.0.113.10", **options)
    described_class.new(root: Rails.root.to_s, environment: environment, host: host, runner: runner, **options)
  end

  let(:kamal_secret_names) { Rails.root.join(".kamal/secrets").read.scan(/^([A-Z_]+)=/).flatten - [ "KAMAL_REGISTRY_PASSWORD" ] }

  it "stores every Kamal secret except the ones only you have, plus the deploy key, under the staging prefix" do
    result = secrets.call

    expected = (kamal_secret_names - described_class::PROVIDED_BY_YOU + %w[DEPLOY_SSH_PRIVATE_KEY DEPLOY_SSH_KNOWN_HOSTS]).map { |name| "STAGING_#{name}" }
    expect(runner.stored.keys).to match_array(expected)
    expect(result.names).to match_array(expected)
    expect(described_class::PROVIDED_BY_YOU - kamal_secret_names).to be_empty
  end

  it "generates values strong enough for EnvValidator and wires the passwords into the connection strings" do
    secrets.call
    values = runner.stored.transform_keys { |name| name.delete_prefix("STAGING_") }

    env = values.merge("APP_HOSTS" => "api.example.com", "CORS_ORIGINS" => "https://app.example.com", "FRONTEND_URL" => "https://app.example.com", "MAILER_FROM" => "a@example.com", "SMTP_ADDRESS" => "smtp.example.com")
    expect(EnvValidator.new(env).errors).to be_empty
    expect(values["DATABASE_URL"]).to eq("postgres://postgres:#{values["POSTGRES_PASSWORD"]}@#{slug}-api-staging-db:5432/#{slug}_api_staging")
    expect(values["REDIS_URL"]).to eq("redis://:#{values["REDIS_PASSWORD"]}@#{slug}-api-staging-redis:6379/1")
    expect(values["SIDEKIQ_REDIS_URL"]).to eq("redis://:#{values["REDIS_PASSWORD"]}@#{slug}-api-staging-redis:6379/0")
    expect(values["DEPLOY_SSH_PRIVATE_KEY"]).to eq("PRIVATE KEY\n")
    expect(values["DEPLOY_SSH_KNOWN_HOSTS"]).to eq(host_key)
  end

  it "uses plain names and the production service for production" do
    secrets(environment: "production").call

    expect(runner.stored.keys).to include("JWT_SECRET", "DEPLOY_SSH_PRIVATE_KEY")
    expect(runner.stored.keys.grep(/STAGING_/)).to be_empty
    expect(runner.stored["DATABASE_URL"]).to end_with("@#{slug}-api-db:5432/#{slug}_api_production")
  end

  it "returns the public key and the host key fingerprint, never the private key" do
    result = secrets.call

    expect(result.public_key).to eq("ssh-ed25519 AAAAPUBLIC #{slug}-api-staging-deploy")
    expect(result.host_fingerprint).to eq("256 SHA256:fingerprint 203.0.113.10 (ED25519)")
    expect(result.to_h.values.join).not_to include("PRIVATE KEY")
  end

  it "targets the given repository" do
    secrets(repository: "octo/app").call

    expect(runner.commands.select { |command| command.first == "gh" }).to all(include("--repo", "octo/app"))
  end

  it "refuses to replace secrets that are already set" do
    runner.existing = %w[STAGING_JWT_SECRET OTHER]

    expect { secrets.call }.to raise_error(described_class::Error, /Already set: STAGING_JWT_SECRET\./)
    expect(runner.stored).to be_empty
  end

  it "replaces them with force" do
    runner.existing = %w[STAGING_JWT_SECRET]

    secrets(force: true).call

    expect(runner.stored).to include("STAGING_JWT_SECRET")
  end

  it "rejects an unknown environment or a malformed host" do
    expect { secrets(environment: "qa").call }.to raise_error(described_class::Error, /Environment must be one of staging, production/)
    expect { secrets(host: "evil; rm -rf /").call }.to raise_error(described_class::Error, /Host must be/)
    expect(runner.commands).to be_empty
  end

  it "stops when the host key cannot be read" do
    runner.instance_variable_set(:@host_key, "")

    expect { secrets.call }.to raise_error(described_class::Error, /Could not read the SSH host key of 203.0.113.10/)
    expect(runner.stored).to be_empty
  end

  it "reports the command that failed" do
    runner.failing = "gh"

    expect { secrets.call }.to raise_error(described_class::Error, "gh failed: boom")
  end
end
