class DocsController < ActionController::API
  SWAGGER_UI_VERSION = "5.17.14".freeze

  def index
    render html: <<~HTML.html_safe, layout: false
      <!doctype html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{ERB::Util.html_escape(Rails.configuration.x.app.slug)}-api · Docs</title>
        <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@#{SWAGGER_UI_VERSION}/swagger-ui.css">
      </head>
      <body>
        <div id="swagger-ui"></div>
        <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@#{SWAGGER_UI_VERSION}/swagger-ui-bundle.js"></script>
        <script>
          SwaggerUIBundle({ url: "#{openapi_spec_path}", dom_id: "#swagger-ui", persistAuthorization: false });
        </script>
      </body>
      </html>
    HTML
  end

  def spec
    send_file Rails.root.join("docs/openapi.yaml"), type: "application/yaml", disposition: "inline"
  end
end
