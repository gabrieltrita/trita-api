require "open3"
require "securerandom"
require "tmpdir"
require "yaml"

class DeploySecrets
  class Error < StandardError; end

  ENVIRONMENTS = %w[staging production].freeze
  HOST_FORMAT = /\A[a-z0-9.-]+\z/i
  IDENTITY_FILE = "config/app.yml".freeze
  SIDEKIQ_WEB_USERNAME = "sidekiq".freeze
  PROVIDED_BY_YOU = %w[SMTP_USERNAME SMTP_PASSWORD SENTRY_DSN APPLE_TEAM_ID APPLE_KEY_ID APPLE_PRIVATE_KEY MERCADO_PAGO_ACCESS_TOKEN MERCADO_PAGO_WEBHOOK_SECRET].freeze

  Result = Struct.new(:names, :public_key, :host_fingerprint, keyword_init: true)

  attr_reader :root, :environment, :host, :repository, :force

  def initialize(root:, environment:, host:, repository: nil, force: false, runner: Open3)
    @root = root
    @environment = environment.to_s
    @host = host.to_s
    @repository = repository
    @force = force
    @runner = runner
  end

  def call
    validate!
    Dir.mktmpdir do |dir|
      key = deploy_key(dir)
      host_key = known_hosts(dir)
      values = app_secrets.merge(
        "DEPLOY_SSH_PRIVATE_KEY" => key[:private],
        "DEPLOY_SSH_KNOWN_HOSTS" => host_key[:lines]
      ).transform_keys { |name| prefix + name }
      refuse_overwrite!(values.keys)
      values.each { |name, value| store(name, value) }
      Result.new(names: values.keys, public_key: key[:public], host_fingerprint: host_key[:fingerprint])
    end
  end

  def prefix
    environment == "staging" ? "STAGING_" : ""
  end

  def service
    environment == "staging" ? "#{slug}-api-staging" : "#{slug}-api"
  end

  def database
    "#{slug}_api_#{environment}"
  end

  private

  def validate!
    raise Error, "Environment must be one of #{ENVIRONMENTS.join(", ")}" unless ENVIRONMENTS.include?(environment)
    raise Error, "Host must be an IP address or a host name" unless HOST_FORMAT.match?(host)
  end

  def slug
    @slug ||= YAML.safe_load_file(File.join(root, IDENTITY_FILE)).fetch("shared").fetch("slug")
  end

  def app_secrets
    postgres = SecureRandom.hex(32)
    redis = SecureRandom.hex(32)
    {
      "SECRET_KEY_BASE" => SecureRandom.hex(64),
      "JWT_SECRET" => SecureRandom.hex(64),
      "AR_ENCRYPTION_PRIMARY_KEY" => SecureRandom.alphanumeric(32),
      "AR_ENCRYPTION_DETERMINISTIC_KEY" => SecureRandom.alphanumeric(32),
      "AR_ENCRYPTION_KEY_DERIVATION_SALT" => SecureRandom.alphanumeric(32),
      "POSTGRES_PASSWORD" => postgres,
      "REDIS_PASSWORD" => redis,
      "DATABASE_URL" => "postgres://postgres:#{postgres}@#{service}-db:5432/#{database}",
      "REDIS_URL" => "redis://:#{redis}@#{service}-redis:6379/1",
      "SIDEKIQ_REDIS_URL" => "redis://:#{redis}@#{service}-redis:6379/0",
      "SIDEKIQ_WEB_USERNAME" => SIDEKIQ_WEB_USERNAME,
      "SIDEKIQ_WEB_PASSWORD" => SecureRandom.hex(16)
    }
  end

  def deploy_key(dir)
    path = File.join(dir, "deploy_key")
    run("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", "#{service}-deploy", "-f", path)
    { private: File.read(path), public: File.read("#{path}.pub").strip }
  end

  def known_hosts(dir)
    lines = run("ssh-keyscan", "-t", "ed25519", host)
    raise Error, "Could not read the SSH host key of #{host}" if lines.strip.empty?

    path = File.join(dir, "known_hosts")
    File.write(path, lines)
    { lines: lines, fingerprint: run("ssh-keygen", "-l", "-f", path).strip }
  end

  def refuse_overwrite!(names)
    taken = names & run("gh", "secret", "list", *repository_args, "--json", "name", "--jq", ".[].name").split
    return if taken.empty? || force

    raise Error, "Already set: #{taken.join(", ")}. Replacing the encryption keys of a database with data makes it unreadable; pass --force only for a new environment"
  end

  def store(name, value)
    run("gh", "secret", "set", name, *repository_args, stdin_data: value)
  end

  def repository_args
    repository ? [ "--repo", repository ] : []
  end

  def run(*command, stdin_data: "")
    output, error, status = @runner.capture3(*command, stdin_data: stdin_data)
    raise Error, "#{command.first} failed: #{error.strip}" unless status.success?

    output
  end
end
