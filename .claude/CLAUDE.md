# trita-api

## Non-negotiable rules

1. **Never write comments.** Not in Ruby, YAML, ERB, shell, Dockerfiles, `.env*`, compose files, specs or anywhere else, and never when updating existing code. Names, small methods and tests carry the intent. Explanations belong in `README.md`, `docs/SECURITY.md`, `docs/openapi.yaml`, commit messages or PR descriptions. The only allowed `#` lines are shebangs (`#!/usr/bin/env ruby`), the Dockerfile parser directives (`# syntax=` and `# check=`) and the Rails-generated header of `db/schema.rb`.
2. **Everything in English**: code, identifiers, tests (`describe`/`context`/`it`), API error messages, emails, locales, logs, docs, commit messages, branch names, PR titles and PR descriptions. Only the chat with the user is in Portuguese.
3. **Client-facing errors carry a stable `code`.** The front end (trita-web) translates by `error.code` and `details[field][].code`, never by message text. Add every new code to the table in `docs/openapi.yaml`.
4. **Every API route is documented in `docs/openapi.yaml`.** `spec/requests/docs_spec.rb` fails otherwise.
5. **Keep the suite green**: `bundle exec rspec` (fails below 100% line or branch coverage), `bin/rubocop`, `bin/brakeman --no-pager`, `bin/bundler-audit`. CI runs all four.
6. Work on a feature branch and open a PR to `main` (repo `gabrieltrita/trita-api`, remote via the `github-gabrieltrita` SSH alias, commits authored with `g.trita.f@gmail.com`).
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
app/controllers/api/v1/auth/   registrations, confirmations, sessions, two_factor, tokens, passwords
app/controllers/api/v1/        me (profile, password, email, export, destroy), roles
app/controllers/api/v1/me/     sessions, two_factor, consents
app/controllers/api/v1/admin/  base (admin + 2FA required), users, audit_logs
app/controllers/docs_controller.rb   Swagger UI at /docs (non-production or ENABLE_API_DOCS=true)
app/jobs/                  MaintenanceCleanupJob (daily, config/schedule.yml)
app/mailers/user_mailer.rb confirmation, registration_attempt, welcome, password_reset, password_changed, email_change_confirmation, email_change_requested, account_locked, two_factor_disabled
app/models/                User (+ concerns/two_factor_authenticatable), RefreshToken, AuditLog, Consent, Current
app/policies/              ApplicationPolicy, UserPolicy, AuditLogPolicy
app/services/auth/         JsonWebToken, TokenIssuer, RefreshTokenRotator, TokenDenylist, TwoFactorChallenge, Unauthorized/InvalidCredentials/InvalidToken/ReauthenticationFailed
app/services/user_data_export.rb
lib/env_validator.rb       production boot validation (EnvValidator)
config/app.yml             app identity (name, slug, domain), read through Rails.configuration.x.app
lib/tasks/encryption.rake  bin/rails encryption:reencrypt
docs/openapi.yaml, docs/SECURITY.md
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
- Email confirmation is required to log in. Sign-up, password reset and confirmation resend always answer the same way whether the email exists or not.

## Security invariants (do not break)

- Personal data is encrypted with Active Record Encryption: `email` deterministic (lookups and unique index), everything else non-deterministic (`first_name`, `last_name`, `phone`, `unconfirmed_email`, `otp_secret`, IPs and user agents). New personal data: `encrypts`, `text` column, add it to `config/initializers/filter_parameter_logging.rb`. Non-deterministic columns cannot be queried.
- Mail jobs receive only the user (GlobalID). Tokens are generated inside `UserMailer`, never passed through `deliver_later`, Redis or logs.
- Roles are read from the database, never from the token. Authorization goes through Pundit; admins cannot change their own role or delete themselves.
- Any password change goes through the `User` callbacks that revoke every session, audit and email the owner. Do not bypass them with `update_columns` on `password_digest` (except `anonymize!`).
- Sensitive actions re-authenticate with `require_current_password!` and, when 2FA is on, `require_second_factor!`.
- Account deletion is anonymization (`User#anonymize!`), never a hard delete, so the audit trail stays consistent.
- `AuditLog` and `Consent` rows are immutable (`readonly?`). Record sensitive events with `AuditLog.record!(action, target:, actor:, metadata:)`; `metadata` never holds personal data and `action` must be in `AuditLog::ACTIONS`.
- New sensitive or unauthenticated endpoints get a Rack::Attack throttle in `config/initializers/rack_attack.rb` (the request body is JSON; use `json_param`).
- Production refuses to boot without strong secrets (`EnvValidator`); add new required variables there and to `.env.example`.

## Conventions

- Never hardcode the app name, slug or domain in code, config, seeds or specs: read `Rails.configuration.x.app` (`name`, `slug`, `domain`). Only `config/app.yml` and the `TritaApi` module name may contain them.
- Responses: `{ data, meta }`; errors through `render_error(status:, code:, message:, details:)` or the exceptions handled in `ErrorHandling`. Validation details: `{ field => [ { code, message } ] }`.
- Serialization with Blueprinter; pagination with Pagy (`pagy(scope)` + `pagination_meta`, `limit` up to 100).
- Controllers live under `Api::V1`; unauthenticated actions use `skip_before_action :authenticate_user!`.
- Request context (`ip_address`, `user_agent`, `request_id`, `user`) lives in `Current`.
- Generators produce UUID keys, RSpec specs and FactoryBot factories (`bin/rails g model Product name:string`).
- Specs: request specs for every endpoint, English descriptions, helpers `auth_headers`, `tokens_for`, `bearer`, `login`, `otp_code`, `json`. Factories: `:user` is confirmed; traits `:unconfirmed`, `:with_2fa`, `:admin` (with 2FA), `:admin_without_2fa`.
- Default locale `:en` only; user-facing copy lives in `config/locales/en.yml` or the mailer views.
- Adding an endpoint: route, controller, policy if needed, Blueprint, `docs/openapi.yaml` entry (plus any new error code), request spec, throttle if sensitive, audit event if sensitive, README "Features and how to use them" section.

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
- Coverage report: `coverage/index.html` locally, `coverage` artifact in CI. `with_sentry` (spec/support/sentry_helpers.rb) initializes Sentry with an in-memory transport for specs that assert on reported errors.

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
