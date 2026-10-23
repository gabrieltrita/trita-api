require "rails_helper"

RSpec.describe "OpenAPI documentation", type: :request do
  let(:spec) { YAML.safe_load_file(Rails.root.join("docs/openapi.yaml")) }

  let(:documented) do
    spec["paths"].flat_map do |path, operations|
      (operations.keys & %w[get post put patch delete]).map { |verb| "#{verb.upcase} /api/v1#{path}" }
    end.sort
  end

  let(:routed) do
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.delete_suffix("(.:format)")
      verb = route.verb.to_s
      next unless path.start_with?("/api/v1") && verb.present?

      "#{verb} #{path.gsub(/:(\w+)/, '{\1}')}"
    end.uniq.sort
  end

  it "documents every API route and no missing route" do
    expect(documented - routed).to be_empty, "Documented without a route: #{documented - routed}"
    expect(routed - documented).to be_empty, "Routes without documentation: #{routed - documented}"
  end

  it "resolves every $ref to an existing component" do
    refs = File.read(Rails.root.join("docs/openapi.yaml")).scan(%r{\$ref: "#/components/(\w+)/(\w+)"}).uniq
    missing = refs.reject { |kind, name| spec.dig("components", kind, name) }
    expect(missing).to be_empty
  end

  it "serves Swagger UI and the spec file" do
    get "/docs"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("swagger-ui", "<title>#{Rails.configuration.x.app.slug}-api · Docs</title>")

    get "/docs/openapi.yaml"
    expect(response).to have_http_status(:ok)
    expect(response.body).to start_with("openapi: 3.1.0")
  end
end
