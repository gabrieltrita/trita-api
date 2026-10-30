module Auth
  module Oauth
    module Providers
      DEFAULT = "google".freeze
      VERIFIERS = { "google" => GoogleVerifier, "apple" => AppleVerifier }.freeze

      def self.supported?(provider)
        VERIFIERS.key?(provider.to_s)
      end

      def self.verify(provider, id_token)
        VERIFIERS.fetch(provider.to_s).call(id_token)
      end
    end
  end
end
