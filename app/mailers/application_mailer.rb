class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM") { "#{app.name} <no-reply@#{app.domain}>" } }
  layout "mailer"

  private

  def app
    Rails.configuration.x.app
  end

  def frontend_url(path = "")
    "#{ENV.fetch("FRONTEND_URL", "http://localhost:5173")}#{path}"
  end
end
