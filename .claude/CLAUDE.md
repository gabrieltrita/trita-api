# trita-api

## Non-negotiable rules

1. **Never write comments.** Not in Ruby, YAML, ERB, shell, Dockerfiles, `.env*`, compose files, specs or anywhere else, and never when updating existing code. Names, small methods and tests carry the intent. Explanations belong in `README.md`, `docs/SECURITY.md`, `docs/openapi.yaml`, commit messages or PR descriptions. The only allowed `#` lines are shebangs (`#!/usr/bin/env ruby`), the Dockerfile parser directives (`# syntax=` and `# check=`) and the Rails-generated header of `db/schema.rb`.
2. **Everything in English**: code, identifiers, tests (`describe`/`context`/`it`), API error messages, emails, locales, logs, docs, commit messages, branch names, PR titles and PR descriptions. Only the chat with the user is in Portuguese.
3. **Client-facing errors carry a stable `code`.** The front end (trita-web) translates by `error.code` and `details[field][].code`, never by message text. Add every new code to the table in `docs/openapi.yaml`.
4. **The API matches `docs/openapi.yaml`.** Every route is documented (`spec/requests/docs_spec.rb`), every response under `/api/v1` is validated against its documented status and schema during request specs, and 100% of the documented responses must be exercised by some spec (`openapi_first`, `spec/support/openapi.rb`). Change the schema together with the response, and add a spec for every status you document.
5. **Keep the suite green**: `bundle exec rspec` (fails below 100% line or branch coverage), `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`. CI runs all four.
6. Branch from `dev` and open every PR against `dev` (`gh pr create --base dev`); never against `main`. `main` only receives `dev` when the owner promotes it, through a release branch: create `release/YYYY-MM-DD` from `dev` and open the PR from it to `main`. Never open a PR whose head is `dev`: the repository deletes head branches on merge, so merging it deletes `dev`. Repo `gabrieltrita/trita-api`, remote via the `github-gabrieltrita` SSH alias, commits authored with `g.trita.f@gmail.com`.
7. **Plan before every change, then go file by file.** Before modifying, adding or removing any file, present the plan and wait for the owner's explicit approval: the files to modify, add and remove; the changes in each; why; other possible implementations described in prose (no code); and the recommended one. After the plan is approved, show a preview of each file's exact change (diff, or full content for a new file) with its explanation and wait for approval of that file before writing it. Approval covers only what was presented; anything else needs a new round. Exception: spec files (`spec/**`) covered by an approved plan can be written without a per-file preview. Read-only investigation needs no approval.
8. **100% test coverage, never less.** SimpleCov (`.simplecov`) enforces 100% line and 100% branch coverage in `bundle exec rspec` and in CI. Every change ships with the specs that keep it at 100%. Never lower the thresholds or add filters, `skip` entries or `:nocov:` to reach them; delete dead code instead, and only remove an unreachable defensive branch with the owner's approval.
9. **Never merge pull requests.** Open the PR, push and report the CI status; the owner always merges. Never run `gh pr merge` or enable auto-merge, including for Dependabot PRs.

## What this is

Base API (Rails 8.1, API-only, Ruby 3.3.3) that every Trita app builds on. The front end is a separate Node project, **trita-web**, which consumes this API. Responsibilities here: authentication, roles, security, privacy (LGPD) and the shared infrastructure for future domain features.

## Stack

PostgreSQL 17 (UUID primary keys everywhere), Redis 7 (cache, Sidekiq, JWT denylist, rate limiting), Sidekiq 8.1 + sidekiq-cron, MailHog (dev email), Adminer, Docker Compose for development. Gems: `jwt`, `bcrypt`, `rotp`, `pundit`, `rack-cors`, `rack-attack`, `pagy`, `blueprinter`, `sentry-ruby`/`sentry-rails`/`sentry-sidekiq`, `rspec-rails`, `factory_bot_rails`, `shoulda-matchers`, `dotenv-rails`.

## Layout

```
app/blueprints/            UserBlueprint (views: default, self, admin), AuditLogBlueprint
app/controllers/concerns/  Authenticatable (Bearer JWT), TokenResponder (body or httpOnly cookie), ErrorHandling, Paginatable
app/controllers/api/v1/auth/   registrations, confirmations, sessions, two_factor, tokens, passwords, oauth
app/controllers/api/v1/        me (profile, password, email, export, destroy), roles
app/controllers/api/v1/me/     sessions, two_factor, consents, identities
app/controllers/api/v1/admin/  base (admin + 2FA required), users, audit_logs
app/controllers/api/v1/notes_controller.rb  example domain module (Note, NotePolicy, NoteBlueprint); see docs/FORKING.md to remove it
app/controllers/docs_controller.rb   Swagger UI at /docs (non-production or ENABLE_API_DOCS=true)
app/controllers/health_controller.rb GET /health (readiness, public); checks in app/services/health_check.rb
app/jobs/                  MaintenanceCleanupJob (daily, config/schedule.yml)
app/mailers/user_mailer.rb confirmation, registration_attempt, welcome, password_reset, password_changed, email_change_confirmation, email_change_requested, account_locked, account_deactivated, account_reactivated, two_factor_disabled
app/models/                User (+ concerns/two_factor_authenticatable), RefreshToken, AuditLog, Consent, Identity, Current
app/policies/              ApplicationPolicy, UserPolicy, AuditLogPolicy
app/services/auth/         JsonWebToken, TokenIssuer, RefreshTokenRotator, TokenDenylist, TwoFactorChallenge, OauthSignin, oauth/JwksVerifier (+ GoogleVerifier, AppleVerifier), oauth/Providers, oauth/AppleRevoker, Unauthorized/InvalidCredentials/InvalidToken/ReauthenticationFailed/ProviderUnavailable
app/services/user_data_export.rb
lib/env_validator.rb       production boot validation (EnvValidator)
config/deploy.yml          Kamal deploy (web, job, Postgres and Redis accessories); name from config/app.yml, server details from the environment
.kamal/secrets             references to environment variables for Kamal, never values
config/deploy.staging.yml  staging destination (bin/kamal ... -d staging); .kamal/secrets.staging reads the same secrets from STAGING_ variables
.github/workflows/deploy.yml   CD: staging from main, production from a version tag on main, and a manual run on main that prepares the server and runs kamal setup; .github/actions/kamal-deploy builds (QEMU for arm64), deploys and checks /health
lib/json_log_formatter.rb  one JSON object per log line (JsonLogFormatter), used when config.x.json_logs is on
lib/sentry_config.rb       Sentry privacy policy (SentryConfig.apply / .scrub)
lib/app_renamer.rb         AppRenamer, used by bin/rename to rename a fork
lib/deploy_secrets.rb      DeploySecrets, used by bin/deploy-secrets to fill an environment's generated repository secrets and deploy key through gh
lib/generators/api_resource/  `bin/rails g api_resource Name field:type`: user-owned resource in the notes shape (templates in templates/*.tt)
config/app.yml             app identity (name, slug, domain), read through Rails.configuration.x.app
config/routes/app.rb       the app's routes, drawn inside /api/v1 by `draw :app`; the base never edits it
lib/tasks/encryption.rake  bin/rails encryption:reencrypt
docs/openapi.yaml, docs/SECURITY.md, docs/FORKING.md (how to start an app from this base)
spec/                      models, requests, mailers, policies, services, controllers (production-only error handling), jobs, lib, tasks; helpers in spec/support (auth_helpers, sentry_helpers)
```

## Authentication model

- Access token: JWT HS256, 15 min, claims `sub`, `sid` (session = refresh token `family_id`), `jti`, `type: "access"`, `iss: "<slug>-api"`. Secrets: `JWT_SECRET` plus optional `JWT_SECRET_PREVIOUS` for rotation. Decoding always passes the expected `type`.
- Refresh token: random 64 bytes, SHA-256 stored, 30 days, rotated on every use within the same `family_id`. `revoked_reason` records why it was revoked; only reuse of a `rotated` token triggers reuse detection (revoke every session, `refresh_token_reused`).
- Revocation is immediate through `Auth::TokenDenylist` in `Rails.cache` (Redis): per `jti` (logout, used 2FA challenge) and per `sid` (session revoked, password change, reuse).
- Authenticated requests reject tokens issued before `users.password_changed_at`.
- Cookie mode: header `X-Token-Transport: cookie` puts the refresh token in `<slug>_refresh` (httpOnly, SameSite=Strict, path `/api/v1/auth`) and removes it from the JSON. The cookie is only read when the header is present (CSRF defence through CORS preflight).
- 2FA: TOTP with replay protection and 10 HMAC'd single-use backup codes. Login with 2FA returns a 5-minute single-use `challenge_token` (`type: "2fa_challenge"`). Admins must have 2FA to use `/api/v1/admin/*` and cannot disable it.
- Lockout: 5 failures lock 15 min, doubling to 24 h; a locked account answers exactly like a wrong password; the owner is emailed; any password change unlocks.
- Deactivation (admin): `deactivated_at` blocks every way of obtaining tokens (answered like a wrong password, without counting a failed attempt) and revokes every session; only an admin reactivates. New sign-in paths must go through `TokenResponder` (`refuse_deactivated!`) or check `deactivated?` themselves.
- Email confirmation is required to log in. Sign-up, password reset and confirmation resend always answer the same way whether the email exists or not.

## Security invariants (do not break)

- Personal data is encrypted with Active Record Encryption: `email` deterministic (lookups and unique index), everything else non-deterministic (`first_name`, `last_name`, `phone`, `unconfirmed_email`, `otp_secret`, IPs and user agents). New personal data: `encrypts`, `text` column, add it to `config/initializers/filter_parameter_logging.rb`. Non-deterministic columns cannot be queried.
- Mail jobs receive only the user (GlobalID). Tokens are generated inside `UserMailer`, never passed through `deliver_later`, Redis or logs.
- Roles are read from the database, never from the token. Authorization goes through Pundit; admins cannot change their own role or delete themselves.
- Any password change goes through the `User` callbacks that revoke every session, audit and email the owner. Do not bypass them with `update_columns` on `password_digest` (except `anonymize!`).
- Sensitive actions re-authenticate with `require_reauthentication!` (the current password; for accounts without a password the 2FA code or a fresh ID token of an identity already linked to the account) and, when 2FA is on, `require_second_factor!`. The code is verified only once per request, because a TOTP code works once.
- Accounts can have no password (`password_digest` is nullable; `User#password_set?`). Any code that reads `password_digest` or `password_salt` must handle `nil`, and a user needs a password or an identity (`login_methods_count`). Never remove the last login method.
- `Identity#provider_uid` is encrypted deterministically, filtered from logs, and never returned by the API or the export.
- The Apple private key (`APPLE_PRIVATE_KEY`) and authorization codes never reach logs or audit metadata; revocation failures only log the exception class and never block account deletion.
- Social login accepts only a verified provider ID token (signature, issuer, audience, expiry, `email_verified`); never trust an email or uid sent by the client. Linking an identity to an unconfirmed account discards its password and sessions first. Third-party HTTP calls have short timeouts, their failures answer 503, and logs carry only the exception class.
- Adding a social provider means a `JwksVerifier` subclass (constants only), one entry in `Auth::Oauth::Providers::VERIFIERS`, a route and a client-ids variable. A provider token only counts as re-authentication when its `sub` matches an identity of the current user, and never for `POST /me/identities`, where the token is the account being linked.
- Account deletion is anonymization (`User#anonymize!`), never a hard delete, so the audit trail stays consistent.
- `AuditLog` and `Consent` rows are immutable (`readonly?`). Record sensitive events with `AuditLog.record!(action, target:, actor:, metadata:)`; `metadata` never holds personal data and `action` must be in `AuditLog::ACTIONS`.
- New sensitive or unauthenticated endpoints get a Rack::Attack throttle in `config/initializers/rack_attack.rb` (the request body is JSON; use `json_param`).
- Production refuses to boot without strong secrets (`EnvValidator`); a new required variable goes into `EnvValidator::REQUIRED`, `config/deploy.yml`, `.kamal/secrets`, `.kamal/secrets.staging` (as `STAGING_`), `.github/workflows/deploy.yml`, `.env.example` and the README in the same change (`spec/config/deploy_spec.rb` and `spec/config/workflows_spec.rb` fail otherwise). `.kamal/secrets` holds references only; never write a value in it.
- Content a user creates (notes, orders, messages) is listed in `User::PERSONAL_DATA`: `UserDataExport` exports it under `content` with `<Model>Blueprint`, and `User#anonymize!` destroys it in the same transaction. Its personal columns are encrypted and filtered from logs.
- Logs never carry personal data: no params, bodies, IPs, user agents, exception messages or job arguments (`JsonLogFormatter` logs only an exception's class; `config.active_job.log_arguments` is off with JSON logs). Identify requests by `request_id` and users by `user_id` (UUID). Log a Hash of safe fields (`Rails.logger.error({ error: e.class.name, ... })`), never an exception message or interpolated values.
- Sentry events never carry personal data. `lib/sentry_config.rb` is the single policy (used by the initializer and by `with_sentry` in specs): `send_default_pii = false`, no client IP, no `Authorization`/`Cookie`/`X-Token-Transport`/`User-Agent` headers, exception and manual messages replaced by `[FILTERED]`, no SQL text or cache keys in breadcrumbs, no Sidekiq job arguments, user reduced to its id. New personal headers, breadcrumb fields or contexts go there, with a spec.

## Conventions

- `/up` is liveness (process running, used by container healthchecks); `/health` is readiness (database, cache, Sidekiq). Only database or cache failures return 503; Sidekiq problems are `degraded` with 200. `/health` returns statuses only, never error details. A new critical dependency goes into `HealthCheck` with a spec for its failure.
- Never hardcode the app name, slug or domain in code, config, seeds or specs: read `Rails.configuration.x.app` (`name`, `slug`, `domain`). Only `config/app.yml` and the `TritaApi` module name may contain them.
- `slug` is lowercase letters and digits only, starting with a letter. A new document that mentions the app name must be added to `AppRenamer::DOCUMENTS`, or `bin/rename` will leave it behind.
- `docs/FORKING.md` is the exception: it names trita-api as the upstream base on purpose, so it is not in `AppRenamer::DOCUMENTS`. Keep it in sync when the fork workflow changes (rename, secrets, boot, merge conflicts).
- Responses: `{ data, meta }`; errors through `render_error(status:, code:, message:, details:)` or the exceptions handled in `ErrorHandling`. Validation details: `{ field => [ { code, message } ] }`.
- Serialization with Blueprinter; pagination with Pagy (`pagy(scope)` + `pagination_meta`, `limit` up to 100).
- Controllers live under `Api::V1`; unauthenticated actions use `skip_before_action :authenticate_user!`.
- Request context (`ip_address`, `user_agent`, `request_id`, `user`) lives in `Current`.
- New user-owned resources start with `bin/rails g api_resource Product name:string`, then the printed steps. Plain Rails generators still produce UUID keys, RSpec specs and FactoryBot factories for anything else.
- Specs: request specs for every endpoint, English descriptions, helpers `auth_headers`, `tokens_for`, `bearer`, `login`, `otp_code`, `json`. Factories: `:user` is confirmed; traits `:unconfirmed`, `:with_2fa`, `:admin` (with 2FA), `:admin_without_2fa`.
- Default locale `:en` only; user-facing copy lives in `config/locales/en.yml` or the mailer views.
- Adding an endpoint: route (in `config/routes/app.rb` for app features), controller, policy if needed, Blueprint, `docs/openapi.yaml` entry (plus any new error code), request spec, throttle if sensitive, audit event if sensitive, README "Features and how to use them" section.

## Running

```bash
cp .env.example .env
docker compose up -d --build
docker compose exec api bin/rails db:seed
docker compose exec api bundle exec rspec
```

- Host ports bind to `127.0.0.1` (`BIND_ADDRESS`) and are configurable (`API_PORT`, `DB_PORT`, `REDIS_PORT`, `MAILHOG_SMTP_PORT`, `MAILHOG_WEB_PORT`, `ADMINER_PORT`). On the owner's machine another project uses 3000/5432/1025/8025, so the local `.env` uses API 3100, Postgres 5433, MailHog 1026/8026, Adminer 8081.
- Compose names containers `<project>-<service>-1` (for example `trita-api-1`); always address services by name (`docker compose exec api`). The Redis cache (JWT denylist, Rack::Attack) is namespaced by `slug`; Sidekiq does not support namespaces, so apps sharing a Redis need separate databases or instances.
- Redis requires `REDIS_PASSWORD`; it must also appear in `REDIS_URL` and `SIDEKIQ_REDIS_URL`.
- Tests can run on the host against the compose Postgres (`.env` points to localhost). Rack::Attack is disabled in tests except in `spec/requests/rack_attack_spec.rb`; the test cache store is `:memory_store`.
- Coverage report: `coverage/index.html` locally, `coverage` artifact in CI. `with_sentry` (spec/support/sentry_helpers.rb) initializes Sentry with the real `SentryConfig`, an in-memory transport and the breadcrumbs logger; `sentry_payload(event)` serializes an event without stacktrace source lines, so leak assertions are not fooled by literals in the spec file itself.
- API contract coverage report: `coverage/openapi_coverage.html` (also in the CI artifact). A partial run (`rspec spec/some_spec.rb`) fails both coverage gates on purpose; run the full suite before trusting a failure.
- Logs: JSON in production (`config.x.json_logs`), text in development unless `LOG_FORMAT=json`. Request lines come from lograge (`config/initializers/lograge.rb`) with `request_id`/`user_id` added in `ApplicationController#append_info_to_payload`; Sidekiq uses its own JSON formatter.

## Gotchas

- Ruby 3.3.3 ships a broken `net-pop` gemspec: `Gemfile.lock` keeps a manual `net-protocol` dependency under `net-pop (0.1.2)`. Keep it after `bundle update`, or the Docker build fails.
- `connection_pool` must move together with Sidekiq, never on its own: 3.x crashed Sidekiq 7.3 (`wrong number of arguments` in `Sidekiq::Scheduled`), while Sidekiq 8.1 requires `>= 3`. Dependabot ignores `connection_pool` majors for this reason. `Rails.cache` (RedisCacheStore) also uses the pool, and CI runs with `:memory_store`, so pool upgrades must be verified in Docker (Sidekiq boot, cache, concurrent requests).
- CI never boots a Sidekiq server or uses Redis for the cache: dependency upgrades touching Sidekiq, Redis or the pool need the Docker end-to-end check before merging.
- `travel`/`travel_to` freeze time; a TOTP code is accepted only once, so specs that need two codes travel 31 seconds.
- `docs/openapi.yaml` must match the routes exactly, including `PUT` aliases generated by `resources`.
- `rescue_from StandardError` in `ErrorHandling` is only registered outside development and test, so the 500 path is tested through a production-like anonymous controller in `spec/controllers/concerns/error_handling_spec.rb`.
- Rotating the deterministic encryption key is not supported in place; see `docs/SECURITY.md`.
- `Auth::JsonWebToken::ISSUER`, `TokenResponder::REFRESH_COOKIE` and `TwoFactorAuthenticatable::OTP_ISSUER` are computed from `config/app.yml` when the classes load: restart after editing it. Changing `slug` in a deployed app invalidates every token, refresh cookie and cached denylist entry.
- The backup code HMAC key is derived with the fixed label `two_factor/backup_codes`; never tie it to the app name, or a rename invalidates every user's backup codes.
- `spec/rails_helper.rb` forces `RAILS_ENV=test` (not `||=`): the api container runs with `RAILS_ENV=development`, and running specs there would load the wrong gem groups and wipe development data. Keep it forced.
- `spec/lib/app_renamer_spec.rb` reads the current identity from `config/app.yml` and renames to neutral slugs (`zetaapp`, `omegaapp`), so it passes in any fork; keep it independent of the name `trita`.
- `config/routes/app.rb` must exist (`draw :app` fails at boot otherwise); keep it even when empty.
- `User::PERSONAL_DATA` must never be empty while the suite enforces 100%: the export's `blueprint_for` would be unreachable. Replace `notes` with the app's first personal-data model in the same change that removes the example.
- The `api_resource` templates mirror the notes module: when a convention changes in `Note*`, apply it to the templates too. `spec/lib/generators/api_resource_generator_spec.rb` checks the output and the OpenAPI anchors (`paths:`, root `security:`, `    Pagination:`, `  responses:`); renaming or moving those keys in `docs/openapi.yaml` breaks the generator.
- CI eager loads (`config.eager_load = ENV["CI"].present?` in test.rb), local runs do not: run `CI=true bundle exec rspec` before pushing anything that adds files under `lib/` or `app/`. `lib/generators` is excluded from autoloading because generators do not follow Zeitwerk naming.
- `oneOf` in the OpenAPI spec needs mutually exclusive variants (use `required` fields), or valid responses fail validation; see `SessionResponse`/`TwoFactorChallengeResponse`.
- `openapi_first` tolerates undocumented 401/404/500 on any route and ignores paths outside `/api/v1/` (`/docs`, `/up`, `/sidekiq`). Requests are not validated strictly, so specs can still send invalid input on purpose.
- The `api_resource` templates produce specs that exercise every response they document; keep that true when editing them.
- `config/environments/production.rb` must not set `config.logger` or `config.log_tags`: it would replace the JSON logger defined in `config/application.rb`.
- In `config/initializers/sidekiq.rb` the JSON formatter is set before `config.redis`, or the Redis connection line is logged as text.
- After adding gems, the running containers need `docker compose exec api bundle install` (or a restart); the entrypoint only installs on start.
- `RedisCacheStore` swallows connection errors (reads miss, writes are dropped), so the cache check writes and reads back a unique key instead of waiting for an exception.
- A stopped Sidekiq stays registered in `Sidekiq::ProcessSet` until its heartbeat expires (about a minute), so `/health` turns `degraded` with that delay.
- `/up` and `/health` are excluded from `config.hosts` checks, the general `req/ip` throttle and lograge; keep that list in sync when adding infrastructure endpoints.
- Sentry 7 with `send_default_pii = false` never collects request bodies, query strings or cookies, but it does send `User-Agent` and `REMOTE_ADDR` unless `SentryConfig` removes them; the scrubbing specs prove both, so a Sentry upgrade that changes this fails CI.
- The ActiveSupport breadcrumbs logger is injected by sentry-rails only at boot; specs inject and detach it inside `with_sentry`.
- `has_secure_password` runs with `validations: false`, so `User` re-declares the password confirmation and the "password or identity" validation; keep both when editing it.
- Specs never reach the network (`webmock/rspec`); stub every external HTTP call, such as Google's JWKS.
- Changing `SECRET_KEY_BASE` invalidates every user's 2FA backup codes (their HMAC key derives from it).
- Kamal's secrets reader only expands `$VAR` and `${VAR}`: `${VAR:-default}` leaves `:-}` in the value, and an unset variable becomes an empty string with no warning. `EnvValidator` is the safety net at boot, so optional secrets are plain `$VAR` references. `.kamal/secrets.staging` mirrors `.kamal/secrets` with `STAGING_` sources (`spec/config/deploy_spec.rb` checks the expanded values).
- Workflows pass secrets to scripts as `env:` data, never as `${{ }}` inside `run:`, and only use `actions/*`, `docker/*`, `ruby/*` and local actions (`spec/config/workflows_spec.rb`). The CI is reusable (`workflow_call`) and the deploy workflow calls it; `main` is not in the CI's own push trigger for that reason.
