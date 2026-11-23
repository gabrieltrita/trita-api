require "yaml"

class AppRenamer
  class Error < StandardError; end

  SLUG_FORMAT = /\A[a-z][a-z0-9]*\z/
  DOMAIN_FORMAT = /\A[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}\z/
  IDENTITY_FILE = "config/app.yml".freeze
  APPLICATION_FILE = "config/application.rb".freeze
  COMPOSE_FILE = "docker-compose.yml".freeze
  DOCUMENTS = %w[README.md docs/README.pt-BR.md docs/SECURITY.md docs/openapi.yaml .claude/CLAUDE.md].freeze

  MANUAL_STEPS = [
    "Generate new secrets in .env: JWT_SECRET (bin/rails secret), AR_ENCRYPTION_* (bin/rails db:encryption:init), REDIS_PASSWORD, DATABASE_PASSWORD, SIDEKIQ_WEB_PASSWORD",
    "Replace the security contact in docs/SECURITY.md",
    "Point origin to the new repository and keep the base as the upstream remote",
    "Create the databases: docker compose up -d --build && docker compose exec api bin/rails db:prepare"
  ].freeze

  attr_reader :root, :slug, :name, :domain

  def initialize(root:, slug:, name: nil, domain: nil)
    @root = root
    @slug = slug.to_s
    @name = name || @slug.capitalize
    @domain = domain || "#{@slug}.dev"
  end

  def call
    validate!
    write(IDENTITY_FILE, { "shared" => { "name" => name, "slug" => slug, "domain" => domain } }.to_yaml.delete_prefix("---\n"))
    rewrite(APPLICATION_FILE) { |text| text.sub("module #{module_for(current["slug"])}", "module #{module_for(slug)}") }
    rewrite(COMPOSE_FILE) { |text| text.sub(/^name: #{current["slug"]}$/, "name: #{slug}").sub("image: #{current["slug"]}-api:", "image: #{slug}-api:") }
    DOCUMENTS.each { |file| rewrite(file) { |text| rename_text(text) } }
    MANUAL_STEPS
  end

  private

  def validate!
    raise Error, "Slug must start with a letter and contain only lowercase letters and digits" unless SLUG_FORMAT.match?(slug)
    raise Error, "Domain must look like example.com" unless DOMAIN_FORMAT.match?(domain)

    missing = [ IDENTITY_FILE, APPLICATION_FILE, COMPOSE_FILE, *DOCUMENTS ].reject { |file| File.exist?(path(file)) }
    raise Error, "Missing files: #{missing.join(", ")}" if missing.any?
    raise Error, "The app is already named #{slug}" if slug == current["slug"]
  end

  def current
    @current ||= YAML.safe_load_file(path(IDENTITY_FILE)).fetch("shared")
  end

  def rename_text(text)
    text
      .gsub(current["domain"], domain)
      .gsub(module_for(current["slug"]), module_for(slug))
      .gsub(/(?<![a-z.])#{current["slug"]}(?![a-z])/, slug)
      .gsub(/\b#{Regexp.escape(current["name"])}\b/, name)
  end

  def module_for(value)
    "#{value.capitalize}Api"
  end

  def rewrite(file)
    write(file, yield(File.read(path(file))))
  end

  def write(file, content)
    File.write(path(file), content)
  end

  def path(file)
    File.join(root, file)
  end
end
