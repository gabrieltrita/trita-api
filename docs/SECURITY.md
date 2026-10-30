# Security

How trita-api protects accounts and personal data, and the procedures to operate it safely.

## Threat model at a glance

| Threat | Mitigation |
|---|---|
| Stolen access token | 15 min lifetime; revocable per token (`jti`) and per session (`sid`) through a Redis denylist |
| Stolen refresh token | Rotation on every use; reusing a rotated token revokes every session (`refresh_token_reused`) |
| XSS stealing the session in the browser | Optional cookie mode: refresh token in an `httpOnly` + `SameSite=Strict` cookie |
| CSRF against the cookie | Cookie is only read with the custom `X-Token-Transport: cookie` header, which forces a CORS preflight |
| Brute force / credential stuffing | Rack::Attack per IP and per email (JSON body), progressive account lockout, owner notified by email |
| Account enumeration | Identical responses for unknown emails on sign-up, login, password reset and confirmation resend |
| Database leak | Personal data encrypted with Active Record Encryption; bcrypt passwords; only hashes of refresh tokens; HMAC'd backup codes |
| Token leak through logs or queues | Email tokens are generated inside the mailer; jobs only carry a GlobalID |
| Account takeover after compromise | Any password change revokes every session; email change requires the password and confirmation at the new address with a notice to the old one |
| Privilege escalation | Role always read from the database; Pundit policies; admins cannot change their own role; admin area requires 2FA |
| Host header attacks | `config.hosts` from `APP_HOSTS` in production |
| Weak production configuration | `EnvValidator` refuses to boot with missing or weak secrets |

## Authentication

- **Access token**: JWT HS256, 15 minutes, claims `sub`, `sid` (session), `jti`, `type=access`, `iss=<slug>-api` (`slug` from `config/app.yml`), so tokens from another app that shares the secret are rejected.
- **Refresh token**: 64 random bytes, 30 days, stored as SHA-256. Each refresh revokes the previous token with reason `rotated` and issues a new one in the same session (`family_id`).
- **Reuse detection** only fires for tokens revoked by rotation. Tokens revoked by logout, password change or anonymization simply return `invalid_token`, so an old device cannot log the user out of a fresh session.
- **2FA**: TOTP (RFC 6238) with 30 s drift tolerance and replay protection (`otp_last_used_step`). Ten single-use backup codes stored as HMAC-SHA256 keyed from `secret_key_base`. Login with 2FA returns a 5-minute single-use `challenge_token`.
- **Lockout**: 5 consecutive failures lock the account for 15 minutes, doubling on each further failure up to 24 hours. A locked account answers exactly like a wrong password. Password reset unlocks it.
- **Google and Apple login** trust only a signed ID token: RS256 signature checked against the provider's published keys (cached; refreshed at most once a minute when an unknown key id shows up), `iss` in the provider's issuer values, `aud` in `GOOGLE_CLIENT_IDS` or `APPLE_CLIENT_IDS`, `exp`, and `email_verified`. Anything else is rejected with the same `oauth_token_invalid`. An unconfirmed local account with the same email is treated as a possible pre-registration: linking discards its password and sessions before confirming it. Linking to a confirmed account is allowed only because the provider asserts ownership of that email. A name sent by the client is only a fallback when the provider token has no name.

## Encrypted data

| Table | Encrypted columns | Mode |
|---|---|---|
| `users` | `email` | deterministic (lookups and unique index) |
| `users` | `first_name`, `last_name`, `phone`, `unconfirmed_email`, `otp_secret` | non-deterministic |
| `refresh_tokens` | `user_agent`, `ip_address` | non-deterministic |
| `audit_logs` | `ip_address`, `user_agent` | non-deterministic |
| `consents` | `ip_address`, `user_agent` | non-deterministic |

`support_unencrypted_data` is disabled, so plain text is never read back. Non-deterministic columns cannot be filtered or sorted in SQL.

New personal data must use `encrypts`, a `text` column, and be added to `config/initializers/filter_parameter_logging.rb`.

## Key rotation

### Active Record Encryption primary key

1. Generate a new key: `bin/rails db:encryption:init`.
2. Set `AR_ENCRYPTION_PRIMARY_KEY="old_key,new_key"` (the last key encrypts, all keys decrypt) and deploy.
3. Re-encrypt existing rows (all models, including the read-only audit and consent tables):
   ```bash
   bin/rails encryption:reencrypt
   ```
4. After every row is re-encrypted, remove the old key: `AR_ENCRYPTION_PRIMARY_KEY="new_key"`.

### Deterministic key

Rails does not support rotating the deterministic key in place. It requires a data migration (decrypt with the old key, re-encrypt with the new one) during a maintenance window. Treat `AR_ENCRYPTION_DETERMINISTIC_KEY` and `AR_ENCRYPTION_KEY_DERIVATION_SALT` as permanent and keep them in a secret manager.

> Losing any `AR_ENCRYPTION_*` value makes the encrypted data unrecoverable. Back them up separately from database backups.

### JWT secret

1. Move the current value to `JWT_SECRET_PREVIOUS` and set a new `JWT_SECRET` (64+ characters: `ruby -rsecurerandom -e 'puts SecureRandom.hex(64)'`).
2. Deploy. Tokens signed with either secret are accepted.
3. After `JWT_ACCESS_TTL_MINUTES` has passed, remove `JWT_SECRET_PREVIOUS`.

Refresh tokens are not JWTs and are unaffected.

### Redis, database and Sidekiq Web passwords

Change the value, restart the services that use it, and rotate any copy in CI or deployment secrets.

## Incident response

| Situation | Action |
|---|---|
| A user account is compromised | Admin: `PATCH /api/v1/admin/users/:id` with a new password (revokes every session) or `DELETE /api/v1/admin/users/:id/two_factor` if the 2FA device was lost |
| `JWT_SECRET` leaked | Rotate without `JWT_SECRET_PREVIOUS` (every access token becomes invalid; clients refresh) |
| Refresh tokens leaked | `bin/rails runner 'RefreshToken.active.update_all(revoked_at: Time.current, revoked_reason: "incident")'` |
| Suspicious activity | `GET /api/v1/admin/audit_logs?action_name=auth.login_failed` and filter by `target_id` |

## Production checklist

- [ ] All variables validated by `EnvValidator` are set (the app refuses to boot otherwise)
- [ ] `CORS_ORIGINS` lists only `https://` front-end origins
- [ ] `APP_HOSTS` lists the API host names
- [ ] TLS terminates in front of the app (`force_ssl` is on)
- [ ] Database and Redis are not publicly reachable and require passwords
- [ ] `SENTRY_DSN` set (no personal data is sent)
- [ ] `/docs` disabled (default in production) unless `ENABLE_API_DOCS=true`
- [ ] Encryption keys backed up in a secret manager

## Reporting a vulnerability

Email g.trita.f@gmail.com with the details. Please do not open a public issue.
