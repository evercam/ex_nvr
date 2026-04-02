---
name: user
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/accounts/user.ex
  - ui/lib/ex_nvr/accounts/user_token.ex
  - ui/lib/ex_nvr/accounts/user_notifier.ex
  - ui/lib/ex_nvr/accounts.ex
  - ui/lib/ex_nvr/authorization.ex
  - ui/lib/ex_nvr_web/controllers/api/user_controller.ex
  - ui/lib/ex_nvr_web/controllers/api/user_json.ex
  - ui/lib/ex_nvr_web/controllers/api/user_session_controller.ex
  - ui/lib/ex_nvr_web/controllers/user_session_controller.ex
  - ui/lib/ex_nvr_web/live/user_live.ex
  - ui/lib/ex_nvr_web/live/user_list_live.ex
  - ui/lib/ex_nvr_web/live/user_login_live.ex
  - ui/lib/ex_nvr_web/live/user_registration_live.ex
  - ui/lib/ex_nvr_web/live/user_reset_password_live.ex
  - ui/lib/ex_nvr_web/live/user_settings_live.ex
  - ui/lib/ex_nvr_web/live/user_confirmation_live.ex
  - ui/lib/ex_nvr_web/live/user_confirmation_instructions_live.ex
  - ui/lib/ex_nvr_web/live/user_forgot_password_live.ex
relates_to:
  concepts: [device]
  features: [user-auth]
---

## Overview

A **User** represents an authenticated person who can interact with ExNVR through the web UI or REST API. Users are the gatekeepers of the system — without a user account, nothing in ExNVR is accessible.

ExNVR has a simple two-role authorization model: **admin** and **user**. Admins have unrestricted access to all resources and operations. Regular users can read most resources (devices, recordings, events) but cannot create, update, or delete devices, manage other users, or access system settings. This is enforced centrally by `ExNVR.Authorization.authorize/3`.

The user system is a standard Phoenix authentication setup (generated via `mix phx.gen.auth` and customized): Bcrypt password hashing, token-based session management, email confirmation, password reset, and email change flows. In addition to browser sessions, ExNVR supports API access tokens (for programmatic access) and webhook tokens (for authenticating event ingestion endpoints).

User registration is available via the API (`POST /api/users`) but the web registration route is commented out in the router — new users are typically created by admins through the `/users` admin panel or the API.

## Data model

### `ExNVR.Accounts.User` (`ui/lib/ex_nvr/accounts/user.ex`)

Primary key: `:id` (`:binary_id`, auto-generated UUID).

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `first_name` | `:string` | — | Optional (required via `:validate_full_name` opt), 2–72 chars |
| `last_name` | `:string` | — | Optional (required via `:validate_full_name` opt), 2–72 chars |
| `username` | `:string` | — | Auto-generated from email (local part before `@`), unique |
| `email` | `:string` | — | Required, unique, max 160 chars, validated for `@` sign |
| `password` | `:string` | — | Virtual field, redacted from logs |
| `hashed_password` | `:string` | — | Bcrypt hash, redacted |
| `confirmed_at` | `:naive_datetime` | — | Set when email is confirmed |
| `role` | `Ecto.Enum` | `:user` | `:admin` or `:user` |
| `language` | `Ecto.Enum` | `:en` | Currently only `:en` is supported |

### `ExNVR.Accounts.UserToken` (`ui/lib/ex_nvr/accounts/user_token.ex`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | `:binary_id` | Primary key |
| `token` | `:binary` | Raw token (session/access/webhook) or SHA-256 hash (email tokens) |
| `context` | `:string` | Token type: `"session"`, `"access"`, `"webhook"`, `"confirm"`, `"reset_password"`, `"change:*"` |
| `sent_to` | `:string` | Email address the token was sent to (for email tokens) |
| `user_id` | `:binary_id` | FK to user |

**Token validity periods:**

| Context | Validity |
|---------|----------|
| Session | 15 days |
| Access (API) | 2 days |
| Confirmation | 7 days |
| Reset password | 1 day |
| Change email | 7 days |
| Webhook | No expiry (manually managed) |

Email tokens (confirm, reset, change) are hashed with SHA-256 before storage — the raw token is sent to the user's email and cannot be reconstructed from the database. Session, access, and webhook tokens are stored as-is (they're delivered via signed cookies or API responses, not email).

## API surface

### REST API

| Method | Path | Action | Auth |
|--------|------|--------|------|
| `POST` | `/api/users/login` | Returns an access token | Public |
| `GET` | `/api/users` | List all users | Admin only |
| `POST` | `/api/users` | Create user | Admin only |
| `GET` | `/api/users/:id` | Show user | Admin only |
| `PUT/PATCH` | `/api/users/:id` | Update user | Admin only |
| `DELETE` | `/api/users/:id` | Delete user | Admin only |

The login endpoint (`UserSessionController.login/2`) accepts `username` (which is actually the email) and `password`, and returns `{access_token: "..."}`. The access token is a base64-encoded random token valid for 2 days.

All user management endpoints (`UserController`) are restricted to admins via `ExNVR.Authorization`. The controller uses a custom `authorization_plug` that checks `authorize(user, :user, :any)` — regular users get a 403 on any user management action.

### LiveView pages

| Path | Module | Access |
|------|--------|--------|
| `/users/login` | `UserLoginLive` | Unauthenticated only |
| `/users/reset-password` | `UserForgotPasswordLive` | Unauthenticated only |
| `/users/reset-password/:token` | `UserResetPasswordLive` | Unauthenticated only |
| `/users/settings` | `UserSettingsLive` | Authenticated |
| `/users/settings/confirm-email/:token` | `UserSettingsLive` | Authenticated |
| `/users/confirm` | `UserConfirmationInstructionsLive` | Any |
| `/users/confirm/:token` | `UserConfirmationLive` | Any |
| `/users` | `UserListLive` | Admin only |
| `/users/:id` | `UserLive` | Admin only |

The admin user management pages (`/users` and `/users/:id`) are protected by both `ensure_authenticated` and `ensure_user_is_admin` on_mount hooks.

## Business logic

### `ExNVR.Accounts` context (`ui/lib/ex_nvr/accounts.ex`)

**Registration** (`register_user/2`):
- Casts email, password, first/last name, language, and role
- Auto-generates `username` from the email local part (before `@`)
- Hashes password with Bcrypt (max 72 bytes)
- Validates email uniqueness

**Password management**:
- `update_user_password/3` — Validates current password, hashes new password, deletes all existing tokens (forces re-login everywhere)
- `reset_user_password/2` — Same as password change but without current password verification (uses a time-limited reset token). Also deletes all tokens.
- Password requirements: 8–72 chars, at least one lowercase, one uppercase, and one digit or punctuation character

**Email change flow**:
1. `apply_user_email/3` — Validates the new email and current password without persisting
2. `deliver_user_update_email_instructions/3` — Sends a confirmation email with a hashed token
3. `update_user_email/2` — Verifies the token, updates the email, and auto-confirms the account

**Token types**:
- **Session tokens** — Generated on browser login, stored as random bytes, verified by checking existence and age (< 15 days)
- **Access tokens** — Generated via `POST /api/users/login`, base64-encoded, valid for 2 days. Used for API authentication.
- **Webhook tokens** — Long-lived tokens for authenticating webhook event ingestion. One per user, manually generated/deleted. No automatic expiry.

**Deletion** (`delete_user/1`):
Uses `Ecto.Multi` to delete all user tokens first, then the user record, in a single transaction.

**Token cleanup** (`delete_all_expired_tokens/0`):
Queries tokens across all contexts that have exceeded their validity period and deletes them in bulk.

### Authorization (`ExNVR.Authorization`)

The authorization module implements a simple role-based system with four rules evaluated in order:

1. Admins can do everything (`:ok` for any resource/action)
2. Regular users cannot access `:user` resource (cannot manage users)
3. Regular users cannot access `:system` resource (cannot manage system settings)
4. Regular users can `:read` any other resource
5. Everything else is denied

This means regular users can view devices, recordings, events, and streams, but cannot create/update/delete them.

## Storage

### Database

SQLite tables:
- `users` — User accounts with hashed passwords and role
- `users_tokens` — All token types (session, access, webhook, email confirmation, password reset, email change)

### Email delivery

Email notifications (confirmation, password reset, email change) are delivered via Swoosh through `ExNVR.Mailer`. The sender is configured as `"ExNVR" <contact@example.com>`. Emails are plain text.

## Business rules

- **Username is derived from email** — The `generate_username/1` function extracts the local part of the email address. The username has a unique constraint but is not directly editable by users.
- **Password change invalidates all sessions** — Both `update_user_password/3` and `reset_user_password/2` delete all tokens for the user, forcing re-authentication on all devices/sessions.
- **Web registration is disabled** — The `/users/register` LiveView route is commented out in the router. New users are created by admins via the admin panel or API.
- **Webhook tokens are singleton** — Each user can have at most one webhook token. `generate_webhook_token/1` creates a new one, `delete_webhook_token/1` removes it. There's no automatic expiry.
- **Email confirmation is optional for access** — The `confirmed_at` field exists but the authentication flow does not appear to require confirmation before granting access. Confirmation is available but not enforced.
- **Timing attack protection** — `User.valid_password?/2` calls `Bcrypt.no_user_verify/0` when no user is found, ensuring constant-time response regardless of whether the email exists.

## Related concepts

- [device](device.md) — Users interact with devices; authorization determines what operations are allowed
