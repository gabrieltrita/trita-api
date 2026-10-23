module SentryHelpers
  def with_sentry
    Sentry.init do |config|
      config.dsn = "http://public@sentry.test/1"
      config.transport.transport_class = Sentry::DummyTransport
      config.background_worker_threads = 0
    end
    yield Sentry.get_current_client.transport
  ensure
    Sentry.close
  end
end

RSpec.configure do |config|
  config.include SentryHelpers
end
