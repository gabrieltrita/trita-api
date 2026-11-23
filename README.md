# trita-api

Base API (Rails 8.1, API-only) for the Trita apps. The front end lives in the separate **trita-web** project (Node).

## Stack

| Service | Purpose | Default URL |
|---|---|---|
| **api** | Rails 8.1 / Puma | http://localhost:3000 |
| **sidekiq** | Background jobs and scheduled jobs (sidekiq-cron) | dashboard at http://localhost:3000/sidekiq |
| **db** | PostgreSQL 17 | localhost:5432 |
| **redis** | Cache, Sidekiq queues, JWT denylist, rate limiting | localhost:6379 |
| **mailhog** | Captures every email sent in development | http://localhost:8025 |
| **adminer** | Web UI for Postgres | http://localhost:8080 |

Every port is published on `127.0.0.1` only. Redis requires a password.

Main gems: `jwt`, `bcrypt`, `rotp` (2FA), `pundit`, `rack-cors`, `rack-attack`, `sidekiq` + `sidekiq-cron`, `pagy`, `blueprinter`, `sentry-rails`, `rspec-rails`.

## Getting started

```bash
cp .env.example .env
```

Replace every `troque-me` value in `.env`:

```bash
bin/rails db:encryption:init                          # AR_ENCRYPTION_* values
ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'          # JWT_SECRET
ruby -rsecurerandom -e 'puts SecureRandom.alphanumeric(32)' # REDIS_PASSWORD, DATABASE_PASSWORD, SIDEKIQ_WEB_PASSWORD
```

`REDIS_PASSWORD` must also be inside `REDIS_URL` and `SIDEKIQ_REDIS_URL` (`redis://:<password>@localhost:6379/1`).

```bash
docker compose up -d --build
docker compose exec api bin/rails db:seed
```

The seed creates a confirmed admin (`ADMIN_EMAIL`, default `admin@<domain>`, / `ADMIN_PASSWORD`) and, in development, `user@<domain>` / `User@123456`, where `<domain>` comes from `config/app.yml`. The admin must enable 2FA (see below) before using the admin endpoints.

If a port is already taken, change `API_PORT`, `DB_PORT`, `REDIS_PORT`, `MAILHOG_SMTP_PORT`, `MAILHOG_WEB_PORT` or `ADMINER_PORT` in `.env`. Use `BIND_ADDRESS=0.0.0.0` only to reach the API from another device on your network.

### Useful commands

```bash
docker compose logs -f api sidekiq
docker compose exec api bin/rails console
docker compose exec api bundle exec rspec
docker compose exec api bin/rails g api_resource Product name:string price:decimal
```

To run Rails on the host while using the containers for services: `docker compose up -d db redis mailhog`, then `bin/rails s` (`.env` points to `localhost`).

### Quality

```bash
bundle exec rspec
bin/rubocop
bin/brakeman --no-pager
bin/bundler-audit
```

GitHub Actions runs all four on every pull request.

`bundle exec rspec` enforces **100% line and branch coverage** with SimpleCov (`.simplecov`) and fails below it, locally and in CI. The HTML report is written to `coverage/index.html`; in CI it is attached to the run as the `coverage` artifact. Keep it at 100% by testing new code, not by lowering the threshold or excluding files; remove dead code instead.

Request specs also enforce the API contract with `openapi_first` (`spec/support/openapi.rb`): every response under `/api/v1` is validated against `docs/openapi.yaml` (documented status and body schema), and the suite fails unless **100% of the documented responses** are exercised by some spec. Undocumented 401, 404 and 500 responses are tolerated on every route. The API coverage report is written to `coverage/openapi_coverage.html`. Documenting a new status therefore needs a spec that triggers it, and changing a response needs the matching schema change.

## Documentation

- **OpenAPI / Swagger UI**: http://localhost:3000/docs (source: [`docs/openapi.yaml`](docs/openapi.yaml)). A spec fails if any route is undocumented.
- **Security model, key rotation and incident response**: [`docs/SECURITY.md`](docs/SECURITY.md).

## Response format

```json
{ "data": { }, "meta": { } }
{ "error": { "code": "validation_failed", "message": "Invalid data", "details": { "password": [ { "code": "too_short", "message": "Password is too short (minimum is 8 characters)" } ] } } }
```

Every message is in English. Clients translate using `error.code` and `details[field][].code`, never the message text. The full list of codes is in the OpenAPI description.

## Project layout

```
app/
  blueprints/        JSON serializers
  controllers/
    concerns/        Authenticatable, TokenResponder, ErrorHandling, Paginatable
    api/v1/auth/     register, confirm, login, two_factor, refresh, logout, passwords
    api/v1/me/       sessions, two_factor, consents, identities
    api/v1/admin/    users, audit_logs
    api/v1/notes_controller.rb   example domain module (see feature 16)
  jobs/              MaintenanceCleanupJob
  mailers/           UserMailer
  models/            User, RefreshToken, AuditLog, Consent, Identity, Current, Note (example)
  policies/          Pundit
  services/auth/     JsonWebToken, TokenIssuer, RefreshTokenRotator, TokenDenylist, TwoFactorChallenge
bin/rename           renames the app after forking (see App identity)
lib/                 EnvValidator, AppRenamer, generators/api_resource, rake tasks
config/app.yml       app identity (name, slug, domain)
config/routes/app.rb the app's own routes (drawn inside /api/v1; the base never edits it)
config/schedule.yml  sidekiq-cron schedule
docs/                openapi.yaml, SECURITY.md, FORKING.md
spec/                RSpec
```

## App identity

`config/app.yml` is the single source of the app's identity; a fork changes these three values:

| Key | Example | Drives |
|---|---|---|
| `name` | `Trita` | Email subjects, default sender name, the 2FA account label in authenticator apps |
| `slug` | `trita` | JWT issuer (`trita-api`), refresh cookie (`trita_refresh`), database names (`trita_api_development`), Redis cache namespace, data export file name, Swagger page title |
| `domain` | `trita.dev` | Default sender `no-reply@<domain>` and the seed users' emails |

`slug` must start with a letter and contain only lowercase letters and digits, because it becomes part of database, cookie, container and image names. Code reads the values through `Rails.configuration.x.app`.

To rename the app after forking, run `bin/rename SLUG [--name NAME] [--domain DOMAIN]` (for example `bin/rename acme`, or `bin/rename minhaloja --name "Minha Loja" --domain minhaloja.com.br`). It rewrites `config/app.yml`, the `TritaApi` module, the Compose project and image names and every mention in `README.md`, `docs/` and `.claude/CLAUDE.md`, validates everything before writing, and prints the manual steps that remain (new secrets, security contact, git remotes, databases). Name defaults to the capitalized slug and domain to `SLUG.dev`.

Starting a new app from this base: follow [docs/FORKING.md](docs/FORKING.md) (repository and `upstream` remote, rename, secrets, first boot, where to put domain code, pulling fixes from the base).

## Production

`Dockerfile` (multi-stage, non-root) is for production; `Dockerfile.dev` is used by docker-compose.

The app refuses to boot in production unless these are set and strong enough: `DATABASE_URL`, `REDIS_URL`, `SIDEKIQ_REDIS_URL`, `SECRET_KEY_BASE` (64+, `bin/rails secret`), `JWT_SECRET` (64+), `AR_ENCRYPTION_*` (32+), `APP_HOSTS`, `CORS_ORIGINS` (https only), `FRONTEND_URL`, `MAILER_FROM`, `SMTP_ADDRESS`, `SIDEKIQ_WEB_USERNAME`, `SIDEKIQ_WEB_PASSWORD` (16+). Optional: `SENTRY_DSN`, `JWT_SECRET_PREVIOUS`, `ENABLE_API_DOCS`, `TERMS_VERSION`, `PRIVACY_VERSION`, `GOOGLE_CLIENT_IDS` (comma-separated Google OAuth client ids: web, iOS, Android; empty disables Google login), `APPLE_CLIENT_IDS` (comma-separated Apple identifiers: the app's bundle id and the web Services ID; empty disables Apple login), `APPLE_TEAM_ID`, `APPLE_KEY_ID` and `APPLE_PRIVATE_KEY` (the Sign in with Apple key: team id, key id and the contents of the `.p8` file with `\n` instead of line breaks; all three or none, used to revoke the Apple token when an account is deleted), `MERCADO_PAGO_ACCESS_TOKEN` (empty disables payments) and `MERCADO_PAGO_WEBHOOK_SECRET` (empty rejects every webhook; see Payments).

Logs go to stdout as one JSON object per line. Each request is a single line (lograge) with `time`, `level`, `method`, `path`, `controller`, `action`, `status`, `duration`, `db`, `view`, `request_id`, `user_id` and, on errors, the exception class:

```json
{"time":"2026-10-23T16:50:34.216Z","level":"INFO","method":"POST","path":"/api/v1/notes","controller":"Api::V1::NotesController","action":"create","status":201,"duration":59.98,"db":8.37,"view":0.13,"request_id":"263d77c3-…","user_id":"2ef8b383-…"}
```

Other lines carry `message` (or `error` with the exception class). Request parameters, bodies, IPs, user agents, exception messages and job arguments are never logged; `request_id` links a line to the audit log and to Sentry. `/up` is not logged. Sidekiq logs JSON too, with its own keys (`ts`, `lvl`, `msg`, `ctx` with the job class, id and duration). Set `RAILS_LOG_LEVEL` to change the level (default `info`).

In development logs stay human-readable; set `LOG_FORMAT=json` to see the production format.

Two health endpoints, both public and outside `/api/v1`:

| Endpoint | Meaning | Use it for |
|---|---|---|
| `GET /up` | The Rails process is running (liveness) | Container healthchecks and restarts (docker-compose uses it) |
| `GET /health` | The app can serve requests (readiness): Postgres, Redis cache and Sidekiq | Load balancers, uptime monitors, deploy checks |

`/health` answers `{"status":"ok","checks":{"database":"ok","cache":"ok","sidekiq":"ok"}}`. A failing database or cache makes it `down` with **503**; Sidekiq without processes, or a queue waiting more than 5 minutes, makes it `degraded` with **200**, because the API still serves requests and only background work is delayed. It never returns error details, is throttled to 60 requests per minute per IP, is allowed for any `Host` and is not logged.

---

### Deploying with Kamal

`config/deploy.yml` runs the API (`web`) and Sidekiq (`job`) behind kamal-proxy with automatic TLS, plus Postgres 17 and Redis 7 as accessories on the same server, with no published ports. The app name comes from `config/app.yml`; everything specific to your server comes from the environment of the machine that runs `bin/kamal`, never from the repository.

Before the first deploy: an Ubuntu server reachable by SSH key with ports 80 and 443 open, a DNS A record for the API host, and a GitHub token with `write:packages` (images go to `ghcr.io`).

Variables to export (shell or password manager; `.kamal/secrets` only holds references to them, never write a value in it): `DEPLOY_HOST`, `DEPLOY_SSH_USER` (default `root`), `DEPLOY_ARCH` (default `amd64`), `APP_HOST`, `KAMAL_REGISTRY_USERNAME`, `KAMAL_REGISTRY_PASSWORD`, `CORS_ORIGINS`, `FRONTEND_URL`, `MAILER_FROM`, `SMTP_ADDRESS`, `SMTP_USERNAME`, `SMTP_PASSWORD`, every secret listed in the production section above, `POSTGRES_PASSWORD` and `REDIS_PASSWORD`, plus the optional ones (`SENTRY_DSN`, `GOOGLE_CLIENT_IDS`, `APPLE_*`, `MERCADO_PAGO_*`). The connection strings carry the passwords, so you build them:

- `DATABASE_URL`: `postgres://postgres:<POSTGRES_PASSWORD>@<slug>-api-db:5432/<slug>_api_production`
- `REDIS_URL`: `redis://:<REDIS_PASSWORD>@<slug>-api-redis:6379/1`
- `SIDEKIQ_REDIS_URL`: the same with `/0`

Commands: `bin/kamal setup` the first time (installs Docker, boots the accessories, the proxy and the app), `bin/kamal deploy` afterwards, `bin/kamal rollback VERSION`, and the aliases `bin/kamal console`, `shell`, `logs` and `dbc`. The web container runs `db:prepare` on start, so migrations apply on every deploy.

Changing `SECRET_KEY_BASE` invalidates every user's 2FA backup codes. Database backups arrive with phase 4.4; until then take `pg_dump` by hand.

### Staging with Kamal

`bin/kamal setup -d staging` and `bin/kamal deploy -d staging` use `config/deploy.staging.yml` on top of `config/deploy.yml`: service `<slug>-api-staging` with its own Postgres and Redis containers, database `<slug>_api_staging`, and `ENABLE_API_DOCS=true`, so Swagger is at `/docs`. Staging can share the server with production or use another one, because `DEPLOY_HOST` comes from your environment.

`.kamal/secrets.staging` reads every secret from a variable with the `STAGING_` prefix (`STAGING_JWT_SECRET`, `STAGING_DATABASE_URL`, `STAGING_POSTGRES_PASSWORD`, ...), so production and staging secrets can live side by side and one can never be used for the other by mistake; only `KAMAL_REGISTRY_PASSWORD` is shared. The variables that are not secrets keep their names (`DEPLOY_HOST`, `APP_HOST`, `CORS_ORIGINS`, `FRONTEND_URL`, ...): export the staging values before the command.

- `STAGING_DATABASE_URL`: `postgres://postgres:<STAGING_POSTGRES_PASSWORD>@<slug>-api-staging-db:5432/<slug>_api_staging`
- `STAGING_REDIS_URL`: `redis://:<STAGING_REDIS_PASSWORD>@<slug>-api-staging-redis:6379/1`, and `STAGING_SIDEKIQ_REDIS_URL` the same with `/0`
- Point `SMTP_ADDRESS` at a test mailbox so staging never emails real users.

Kamal does not warn about a secret that was not exported: it reaches the container empty, `EnvValidator` refuses to boot, the health check fails and the deploy stops with the previous version still running.

### Continuous deployment

`.github/workflows/deploy.yml` runs the CI and then deploys: a push to `main` goes to **staging**, and a version tag (`0.3.0`, no `v`) goes to **production**, only if the tagged commit is on `main`. Production has no other gate, so creating the tag is the approval. A job is skipped when its server is not configured (`DEPLOY_HOST` for production, `STAGING_DEPLOY_HOST` for staging). Images are pushed to `ghcr.io` with the workflow token, so no registry token is stored; if the package was first created with a personal token, give this repository access to it in the package settings.

The first setup of each environment also runs from GitHub: Actions, Deploy, Run workflow on `main`, choosing `staging` or `production`. That run connects with the same deploy key, prepares the server with `.github/actions/kamal-deploy/prepare-server.sh` (installs Docker when it is missing, adds the deploy user to the `docker` group and opens ports 80 and 443 in iptables, saving the rules when `netfilter-persistent` is there, as on Oracle Cloud images) and then runs `bin/kamal setup` instead of `bin/kamal deploy`. It is safe to run again. Pushes and tags keep running `bin/kamal deploy`. When `DEPLOY_ARCH` is `arm64` (Ampere, Graviton), the action sets up QEMU so the amd64 runner can build the image; the first build takes a while, later ones reuse the cache. `bin/kamal setup` from your machine still works the same way.

Repository variables (Settings, Secrets and variables, Actions): `DEPLOY_HOST`, `DEPLOY_SSH_USER`, `APP_HOST`, `CORS_ORIGINS`, `FRONTEND_URL`, `MAILER_FROM`, `SMTP_ADDRESS` and the optional `DEPLOY_ARCH`, `SMTP_PORT`, `GOOGLE_CLIENT_IDS`, `APPLE_CLIENT_IDS`. Staging uses the same names with the `STAGING_` prefix.

Repository secrets: the ones listed under "Deploying with Kamal" (production, plain names), the same with the `STAGING_` prefix for staging, and for each environment `DEPLOY_SSH_PRIVATE_KEY` and `DEPLOY_SSH_KNOWN_HOSTS` (`STAGING_DEPLOY_SSH_PRIVATE_KEY`, `STAGING_DEPLOY_SSH_KNOWN_HOSTS`).

`bin/deploy-secrets staging|production HOST [--repo OWNER/NAME]` fills the repository secrets that need no outside account, through the GitHub CLI (`gh auth login` first), and never prints a value: `SECRET_KEY_BASE`, `JWT_SECRET`, the three `AR_ENCRYPTION_*` keys, `POSTGRES_PASSWORD`, `REDIS_PASSWORD`, `DATABASE_URL`, `REDIS_URL` and `SIDEKIQ_REDIS_URL` built with those passwords, `SIDEKIQ_WEB_USERNAME` (`sidekiq`) and `SIDEKIQ_WEB_PASSWORD`, plus a new ed25519 deploy key (`DEPLOY_SSH_PRIVATE_KEY`) and the server's host key (`DEPLOY_SSH_KNOWN_HOSTS`, from `ssh-keyscan`), all with the `STAGING_` prefix for staging. It prints the public key to append to `~/.ssh/authorized_keys` of the deploy user, the host key fingerprint to compare with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server, and the secrets left to you (`SMTP_USERNAME`, `SMTP_PASSWORD`, and the optional `SENTRY_DSN` and `APPLE_*`). It refuses to replace secrets that already exist unless you pass `--force`, because new encryption keys make an existing database unreadable. It needs only Ruby, OpenSSH and `gh`, so it runs in a GitHub Codespace when you are away from your machine.

Deploy user on the server (once per server), if you do not use the image's default sudo user (`ubuntu` on Oracle Cloud and AWS, which the setup run adds to the `docker` group itself):

```bash
adduser --disabled-password --gecos "" deploy
usermod -aG docker deploy
install -d -m 700 -o deploy -g deploy /home/deploy/.ssh
```

By hand instead of `bin/deploy-secrets`: `ssh-keygen -t ed25519 -N "" -C ci-deploy -f deploy_key`, append `deploy_key.pub` to `/home/deploy/.ssh/authorized_keys`, run `ssh-keyscan -t ed25519 <host> > known_hosts` and check its fingerprint against `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on the server, then `gh secret set DEPLOY_SSH_PRIVATE_KEY < deploy_key` and `gh secret set DEPLOY_SSH_KNOWN_HOSTS < known_hosts` (and delete the local files). Set `DEPLOY_SSH_USER` to `deploy`. Members of the `docker` group are root-equivalent on that server, so use a key that is only for this.

Releasing: promote `dev` with a `release/YYYY-MM-DD` branch and a PR to `main`; the merge deploys staging; when staging looks right, `git tag 0.3.0 origin/main && git push origin 0.3.0` deploys production. Database backups arrive with phase 4.4.

## Features and how to use them

All paths below are relative to `/api/v1`. Authenticated calls send `Authorization: Bearer <access_token>`.

### 1. Sign-up with email confirmation

```http
POST /auth/register
{ "email": "ana@example.com", "password": "Secret@123", "password_confirmation": "Secret@123",
  "first_name": "Ana", "last_name": "Silva", "phone": "+5511999990000",
  "accept_terms": true, "accept_privacy": true, "accept_marketing": false }
```

- Always answers `202` when the payload is valid, whether or not the email exists, so accounts cannot be enumerated.
- The email owner receives a confirmation link `FRONTEND_URL/confirm-email?token=...` (or a "sign-up attempt" notice if the account already exists).
- Accepting `terms` and `privacy` is mandatory and stored as consent history.
- The front end reads the token from the URL and calls:

```http
POST /auth/confirm        { "token": "..." }   -> 200 with user + tokens (signed in)
POST /auth/confirm/resend { "email": "..." }   -> always 202
```

Unconfirmed sign-ups are deleted after 7 days.

### 2. Login, tokens and refresh

```http
POST /auth/login { "email": "ana@example.com", "password": "Secret@123" }
```

```json
{ "data": { "user": { }, "tokens": { "token_type": "Bearer", "access_token": "eyJ...", "expires_in": 900,
  "expires_at": "...", "refresh_token": "..." }, "two_factor_setup_required": false } }
```

- `access_token` lasts 15 minutes. On a `401`, call refresh once and retry the request.
- `refresh_token` lasts 30 days and is replaced on every refresh. Reusing an old one revokes every session (`refresh_token_reused`).
- An unconfirmed email returns `403 email_not_confirmed` (only after the right password).

```http
POST /auth/refresh { "refresh_token": "..." }
```

### 3. Cookie mode for browsers (recommended for trita-web)

Send `X-Token-Transport: cookie` on login, two_factor, confirm, refresh and `PATCH /me/password`, with `credentials: "include"`:

```js
await fetch(`${API}/auth/login`, {
  method: "POST",
  credentials: "include",
  headers: { "Content-Type": "application/json", "X-Token-Transport": "cookie" },
  body: JSON.stringify({ email, password }),
});
await fetch(`${API}/auth/refresh`, { method: "POST", credentials: "include", headers: { "X-Token-Transport": "cookie" } });
```

The refresh token goes into an `httpOnly`, `SameSite=Strict` cookie that JavaScript cannot read, and is removed from the JSON. Keep the access token in memory only. Without the header the cookie is ignored (CSRF protection).

A Node BFF can instead use the default body mode and keep the refresh token in its own server-side cookie.

### 4. Two-factor authentication (TOTP)

Enable it:

```http
POST /me/two_factor/setup  { "current_password": "..." }  -> { "secret", "provisioning_uri" }
POST /me/two_factor/enable { "code": "123456" }           -> { "backup_codes": [10 codes] }
```

Render `provisioning_uri` as a QR code for Google Authenticator, 1Password, Authy, etc. Show the backup codes only once.

Log in with 2FA:

```http
POST /auth/login      -> { "two_factor_required": true, "challenge_token": "...", "expires_in": 300 }
POST /auth/two_factor { "challenge_token": "...", "code": "123456" }   -> user + tokens
```

`code` also accepts a backup code (single use). Other endpoints: `GET /me/two_factor`, `POST /me/two_factor/backup_codes`, `DELETE /me/two_factor` (password + code; not allowed for admins).

**2FA is mandatory for admins**: admin endpoints return `403 two_factor_setup_required` until it is enabled, and the login response carries `two_factor_setup_required: true`.

### 5. Logout and sessions per device

```http
DELETE /auth/logout                          -> ends this session immediately
DELETE /auth/logout { "all_devices": true }  -> ends every session
GET    /me/sessions                          -> [{ id, current, user_agent, ip_address, started_at, last_activity_at }]
DELETE /me/sessions/:id                      -> ends that device immediately
```

Revoked access tokens stop working at once (Redis denylist), not only when they expire.

### 6. Password recovery and change

```http
POST  /auth/password/forgot { "email": "..." }                                -> always 202
POST  /auth/password/reset  { "token": "...", "password": "...", "password_confirmation": "..." }
PATCH /me/password          { "current_password": "...", "password": "...", "password_confirmation": "..." }
```

- The reset link (`FRONTEND_URL/reset-password?token=...`) lasts 30 minutes and works once.
- Any password change (reset, user or admin) revokes every session, unlocks the account and emails the owner.
- `PATCH /me/password` returns a fresh session.

Passwords need 8 to 72 characters with uppercase, lowercase and a digit.

### 7. Profile and email change

```http
GET   /me
PATCH /me       { "first_name": "...", "last_name": "...", "phone": "...", "time_zone": "America/Sao_Paulo" }
PATCH /me/email { "email": "new@example.com", "current_password": "..." }   -> 202
POST  /auth/email/confirm { "token": "..." }
```

`time_zone` is an IANA name (`America/Sao_Paulo` by default, `inclusion` for anything else) that features such as reminders use to pick the user's local time. Only `GET /me` returns it, and anonymization resets it.

The new email only takes effect after the link sent to it (`FRONTEND_URL/confirm-email-change?token=...`) is confirmed. The current address gets a notice. `GET /me` shows `pending_email` meanwhile.

### 8. Account lockout and rate limiting

- 5 wrong passwords (or 2FA codes) lock the account for 15 minutes, doubling up to 24 hours. A locked account answers like a wrong password and the owner is emailed. Admins can unlock with `POST /admin/users/:id/unlock`.
- Rack::Attack limits login per IP and per email, 2FA attempts, refresh, sign-up, confirmation, password recovery and sensitive `/me` actions. Throttled requests get `429 rate_limited` with `Retry-After`.

### 9. Roles and authorization

- Roles: `user` (default) and `admin`. `GET /roles` lists them.
- Public sign-up never creates admins. Admins cannot change their own role or delete themselves.
- New roles: add them to the enum in `app/models/user.rb`, to `roles.*` in `config/locales/en.yml`, and to the policies in `app/policies`.

### 10. Admin area (admin with 2FA)

```http
GET    /admin/users?page=1&limit=20&role=admin&email=ana@example.com&status=deactivated
POST   /admin/users              { "email", "first_name", "password", "role" }   (created already confirmed)
GET    /admin/users/:id
PATCH  /admin/users/:id          { "role": "admin" } or { "password": "..." }
DELETE /admin/users/:id          (anonymizes)
POST   /admin/users/:id/unlock
POST   /admin/users/:id/deactivate   (suspends the account, keeping its data)
POST   /admin/users/:id/reactivate
DELETE /admin/users/:id/two_factor   (lost device: resets 2FA and ends the user's sessions)
GET    /admin/audit_logs?action_name=user.role_changed&actor_id=...&target_id=...&from=2026-10-01&to=2026-10-31
```

Name and phone are encrypted non-deterministically, so the user list can only filter by role, exact email and status (`active` or `deactivated`).

Deactivating an account sets `deactivated_at`, revokes every session and emails the owner (`account_deactivated`). Until it is reactivated (`account_reactivated` email), login, refresh, social login, email confirmation and the 2FA step answer `401 invalid_credentials`, exactly like a wrong password, without counting as a failed attempt; access tokens already issued answer `401 invalid_token`. Both actions are audited (`user.deactivated`, `user.reactivated`), admins cannot deactivate themselves, and repeating an action returns the user unchanged. Anonymization (`DELETE`) remains the irreversible option.

### 11. Audit log

Every sensitive event is recorded with actor, target, IP, user agent and request id (IP and user agent encrypted): logins and failures, lockouts, logouts, token reuse, registration, confirmation, role, password and email changes, 2FA changes, session revocations, identity unlinks, consents, exports and anonymizations. Records are immutable and never contain personal data in `metadata`. Query them at `GET /admin/audit_logs`.

### 12. Privacy (LGPD)

```http
GET    /me/consents                                   -> current status per kind
POST   /me/consents { "kind": "marketing", "granted": true }
GET    /me/export                                     -> JSON file with every piece of the user's data
DELETE /me { "current_password": "...", "code": "123456 if 2FA is on" }
```

- Consents (`terms`, `privacy`, `marketing`) are versioned (`TERMS_VERSION`, `PRIVACY_VERSION`) and kept as history. Required consents cannot be revoked; closing the account is the way out.
- Deleting an account anonymizes it: personal data is wiped, sessions end, and the technical record stays so the audit trail remains consistent.
- Personal data is encrypted at rest (see `docs/SECURITY.md`).

### 13. Emails

Sent through Sidekiq (`mailers` queue); in development they show up in MailHog. Emails: confirmation, sign-up attempt, welcome, password reset, password changed, email change confirmation and notice, account locked, 2FA disabled. Links point to `FRONTEND_URL`, so trita-web must implement `/login`, `/forgot-password`, `/reset-password`, `/confirm-email` and `/confirm-email-change`.

### 14. Scheduled maintenance

`MaintenanceCleanupJob` runs daily at 03:00 (São Paulo) via sidekiq-cron (`config/schedule.yml`): deletes expired refresh tokens and sign-ups unconfirmed for more than 7 days. Scheduled jobs are visible in the Sidekiq dashboard (basic auth with `SIDEKIQ_WEB_USERNAME` / `SIDEKIQ_WEB_PASSWORD`).

### 15. Error monitoring and logs

Set `SENTRY_DSN` to enable Sentry for Rails and Sidekiq. Events carry the exception class, the stacktrace, the request method, URL path and safe headers, the `request_id` tag, the user id and breadcrumbs of what ran before the error (controller, timings, cache hits and SQL statement names). They never carry exception or manual messages (replaced by `[FILTERED]`), request bodies, query strings, cookies, `Authorization`, `X-Token-Transport`, `User-Agent`, the client IP, SQL text, cache keys (Rack::Attack keys contain emails) or Sidekiq job arguments. The policy lives in `lib/sentry_config.rb` and is covered by specs.

Logs are structured JSON in production with no personal data (see "Production"). Find everything about one request by its `request_id`, which is also returned in the `X-Request-Id` response header, stored in audit log entries and attached to Sentry events.

### 16. Notes (example domain module)

A small resource that shows every convention a new feature follows; remove it when starting a real app (see "Removing the example module" in `docs/FORKING.md`).

```http
GET    /notes?page=1&limit=20
POST   /notes          { "title": "Groceries", "body": "Milk" }
GET    /notes/:id
PATCH  /notes/:id      { "title": "Renamed" }
DELETE /notes/:id
```

- Each note belongs to the current user, taken from the session; a `user_id` in the body is ignored.
- Another user's note answers `404 not_found` (not 403), even for admins, so ids cannot be probed.
- `title` (required, up to 200) and `body` (up to 10,000) are encrypted at rest and filtered from logs.
- Listed in `User::PERSONAL_DATA`: included under `content.notes` in `GET /me/export` and deleted when the account is anonymized.
- Routes live in `config/routes/app.rb`; the code is `Note`, `NotePolicy`, `NoteBlueprint` and `Api::V1::NotesController`, with request, model and policy specs.

### 17. Resource generator

```bash
bin/rails g api_resource Product name:string price:decimal active:boolean
```

Generates a resource owned by the current user in the shape of the notes example: migration (UUID key, `user_id`, `null: false` columns, list index), model, policy (owner only, 404 for anyone else), blueprint, paginated CRUD controller, the route in `config/routes/app.rb`, the OpenAPI tag, paths, schemas and response, a factory and request, model and policy specs. The generated code passes the suite at 100% line and branch coverage and RuboCop.

Supported types: `string`, `text`, `integer`, `float`, `decimal`, `boolean`, `date`, `datetime`. At least one attribute must not be boolean; namespaced names are rejected. Afterwards the generator prints the manual steps: add `has_many` to `User`, and for personal data switch the columns to `text`, add `encrypts`, filter them from logs and list the association in `User::PERSONAL_DATA`.

### 18. Health checks

`GET /health` reports whether the database, the cache and Sidekiq are working (see "Production" for statuses, HTTP codes and where to use it, and `/up` for liveness).

### 19. Social identities and passwordless accounts

An account can be linked to Google or Apple identities and can have no password at all.

```http
GET    /me/identities                                   -> linked providers (id, provider, email_at_link, created_at)
POST   /me/identities { "provider": "google", "id_token": "...", "current_password": "..." } -> 201
DELETE /me/identities/:id { "current_password": "..." } -> 204
```

- `GET /me` returns `password_set`; the front end uses it to offer "set a password" instead of "change password".
- Sensitive actions (`PATCH /me/password`, `PATCH /me/email`, `DELETE /me`, 2FA setup, disable and backup codes, unlinking an identity) re-authenticate with `current_password` when the account has a password. Accounts without a password send the 2FA `code` instead, or a fresh provider ID token (`provider` + `id_token`) of an account already linked to them. An account with none of these gets `reauthentication_unavailable` (422). A wrong token or one that belongs to another account gets `invalid_provider_token` (422), and `provider_unavailable` (422) means the provider could not be reached, so retry.
- `PATCH /me/password` also sets the first password of a passwordless account.
- `POST /me/identities` links a provider account while logged in, even when its email differs from the user's. It re-authenticates with the password or the 2FA code only, because `id_token` is the account being linked; an account that only has Google and no 2FA first sets a password or enables 2FA (both accept the provider token). A provider account can belong to one user, and a user can have one account per provider: otherwise `identity_already_linked` (422).
- The only way to log in cannot be removed: the request fails with `last_login_method` (422).
- Each user can link one identity per provider, and a provider account can belong to one user. The provider's user id is encrypted deterministically (lookup and unique index) and is never returned by the API or the data export; the linked email is encrypted too.
- Identities are listed in `User::PERSONAL_DATA`: they appear in the data export under `content.identities` and are destroyed on anonymization. Unlinking is audited as `identity.unlinked`.

#### Login with Google

```http
POST /auth/oauth/google { "id_token": "...", "accept_terms": true, "accept_privacy": true, "accept_marketing": false }
```

The front end (Google Identity Services on the web, the SDK on mobile) obtains the Google **ID token** and sends it here; the API never redirects. The API checks the signature against Google's keys (cached), the issuer, that the audience is one of `GOOGLE_CLIENT_IDS`, the expiry and that the email is verified. The response is the same as the password login (body or cookie mode).

- Known Google account: logs in.
- Same email as a confirmed account: the identity is linked, the owner is emailed and audited as `identity.linked`.
- Same email as an **unconfirmed** account (possible pre-registration by someone else): the identity is linked, the password and every session of that account are discarded and the email is marked confirmed.
- New email: creates a confirmed account without a password. `accept_terms` and `accept_privacy` are required in this case only (`validation_failed`, `details.accept_terms[].code = required`).
- 2FA still applies: an account with 2FA gets the usual `challenge_token`.
- Errors: `oauth_token_invalid` (401), `oauth_email_unverified` (401), `oauth_provider_unavailable` (503, Google's keys could not be fetched). Throttled to 10 requests per minute per IP.

#### Login with Apple

```http
POST /auth/oauth/apple { "id_token": "...", "first_name": "...", "last_name": "...", "accept_terms": true, "accept_privacy": true }
```

Same flow, rules and errors as Google, with the Apple identity token. Differences:

- Apple does not put the name in the token. It hands it to the app only on the first authorization, so the client sends `first_name` and `last_name` in the body; they are used only when the account is created and only when the token has no name (the token always wins).
- The user may hide the email: the account is then created with an `@privaterelay.appleid.com` address, which never matches an existing account, so no automatic link happens. The first name falls back to `User`. Emails to that address only reach the real inbox if your sending domain is registered with Apple's private email relay service (Apple Developer portal, Sign in with Apple, Email Sources).
- **Account deletion and the Apple token.** App Store rules require revoking the Apple token when an account is deleted. Right before calling `DELETE /me`, have the app run Sign in with Apple again and send the fresh `authorization_code` (and `apple_client_id`, the bundle id or Services ID that produced it, when it is not the first of `APPLE_CLIENT_IDS`):

  ```http
  DELETE /me { "current_password": "...", "apple_authorization_code": "...", "apple_client_id": "com.example.app" }
  ```

  Revocation is best effort and never blocks the deletion: the audit entry `user.anonymized` records `apple_token_revoked` as `true` or `false` (it is absent when the user has no Apple identity or sent no code). Deletions made by an admin cannot revoke anything.

### 20. Payments (Pix and credit card with Mercado Pago)

Payments are off until `MERCADO_PAGO_ACCESS_TOKEN` is set; meanwhile the payment endpoints answer `503 payments_unavailable` and nothing leaves the server.

The amount is always decided by the server. Domain code (an order, an invoice) or an admin creates the payment, and the user only chooses how to pay:

```ruby
Payment.create!(user: user, payable: order, amount_cents: 15_000, description: "Order #42")
```

```http
POST /admin/payments { "user_id": "...", "amount_cents": 15000, "description": "Backend MVP" }   -> 201
GET  /payments
GET  /payments/:id
POST /payments/:id/pix  { "payer_document": "12345678909" }                                       -> QR code
POST /payments/:id/card { "card_token": "...", "payment_method_id": "visa", "issuer_id": "25", "installments": 3, "payer_document": "..." }
POST /admin/payments/:id/refund
```

- **Pix** returns `pix_qr_code` (copy and paste), `pix_qr_code_base64` (image) and `pix_expires_at` (30 minutes). The status stays `pending` until Mercado Pago confirms it.
- **Card**: the front end tokenizes the card with the Mercado Pago SDK (Card Payment Brick or `MercadoPago.js`) using the public key; the card number and CVV never reach the API. The answer carries the decision: `approved`, `rejected` (see `status_detail`, for example `cc_rejected_insufficient_amount`) or `pending` (under review). Installments are capped at 12.
- Statuses: `created`, `pending`, `approved`, `rejected`, `cancelled`, `refunded`, `charged_back`. Only `created` and `rejected` payments can be paid (`409 payment_not_payable` otherwise), and only `approved` ones refunded (`409 payment_not_refundable`). A request the provider refuses, such as an expired card token, answers `422 payment_request_invalid`.
- **Webhook**: in the Mercado Pago panel (Your integrations, Webhooks) point the "Payments" event to `https://<APP_HOST>/api/v1/webhooks/mercado_pago` and copy the secret it shows into `MERCADO_PAGO_WEBHOOK_SECRET`. Notifications without a valid `x-signature` answer `401 webhook_signature_invalid`. A valid one only enqueues `PaymentSyncJob`, which fetches the payment from Mercado Pago; the body is never trusted.
- `PaymentReconciliationJob` runs every hour (`config/schedule.yml`) and syncs payments that have been `pending` for 15 minutes, so a lost webhook only delays an update.
- Every charge and refund call sends an `X-Idempotency-Key`, so a double click never charges twice. Mercado Pago calls time out after 5 seconds and answer `503 payments_unavailable`.
- Audit events: `payment.created`, `payment.attempted`, `payment.status_changed`, `payment.refunded`.
- Payments are financial records the law requires you to keep: they are not in `User::PERSONAL_DATA`, survive account anonymization (a user with payments cannot be hard deleted) and appear under `payments` in `GET /me/export`. They store no CPF or email, only the card brand and last four digits.
- Another gateway means a class with the same four methods as `Payments::Gateways::MercadoPago` (`create_pix`, `create_card`, `fetch`, `refund`) returning `Payments::GatewayResult`, selected in `Payments::Gateway.current`.
- Test with the test credentials from the Mercado Pago panel and its test cards before going live.
