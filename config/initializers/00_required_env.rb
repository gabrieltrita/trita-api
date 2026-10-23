require Rails.root.join("lib/env_validator").to_s

EnvValidator.validate! if Rails.env.production? && ENV["SKIP_ENV_VALIDATION"] != "true"
