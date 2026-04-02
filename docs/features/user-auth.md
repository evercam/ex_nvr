---
name: user-auth
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/accounts.ex
  - ui/lib/ex_nvr/accounts/**/*.ex
  - ui/lib/ex_nvr/authorization.ex
  - ui/lib/ex_nvr_web/user_auth.ex
  - ui/lib/ex_nvr_web/controllers/api/user_controller.ex
  - ui/lib/ex_nvr_web/controllers/api/user_json.ex
  - ui/lib/ex_nvr_web/controllers/api/user_session_controller.ex
  - ui/lib/ex_nvr_web/controllers/user_session_controller.ex
  - ui/lib/ex_nvr_web/live/user_login_live.ex
  - ui/lib/ex_nvr_web/live/user_settings_live.ex
  - ui/lib/ex_nvr_web/live/user_list_live.ex
  - ui/lib/ex_nvr_web/live/user_live.ex
relates_to:
  concepts: [user]
  features: []
---

## Overview

**User auth** handles authentication, authorization, and user management in ExNVR. It determines who can access the system, what they can do, and how they prove their identity — through browser sessions, API access tokens, or webhook tokens.

The system uses a standard Phoenix authentication setup (originally from `mix phx.gen.auth`) with Bcrypt password hashing, customized for ExNVR's two-role model: **admin** (full access) and **user** (read-only access to most resources). Without auth, the entire system would be open to anyone on the network.

Three authentication mechanisms serve different client types:
1. **Browser sessions** — Cookie-based sessions for the LiveView UI (15 days, optional remember-me)
2. **API access tokens** — Short-lived base64 tokens for programmatic REST API access (2 days)
3. **Webhook tokens** — Long-lived tokens for authenticating event ingestion endpoints (no expiry)

## How it works

### Authentication flow (browser)

1. User visits `/users/login` → `UserLoginLive` renders email/password form
2. Form posts to `POST /users/log_in` → `UserSessionController.create/2`
3. `Accounts.get_user_by_email_and_password/2` validates credentials via Bcrypt
4. `UserAuth.log_in_user/3` generates a session token, renews the session (prevents fixation), sets the cookie, and optionally writes a remember-me cookie (signed, 15 days)
5. Redirects to the stored return path or `/dashboard`

### Authentication flow (API)

1. Client sends `POST /api/users/login` with `username` (email) and `password`
2. `API.UserSessionController.login/2` validates credentials
3. `Accounts.generate_user_access_token/1` creates a token (random bytes, stored in DB)
4. Returns `{access_token: Base.url_encode64(token)}` — valid for 2 days
5. Subsequent API requests include `Authorization: Bearer <access_token>` header

### Authentication flow (webhook)

1. Admin generates a webhook token via the Events page's "Webhook Config" tab
2. `Accounts.generate_webhook_token/1` creates a long-lived token (one per user)
3. External systems include the token as `Authorization: Bearer <token>` or `?token=<token>` query param
4. `UserAuth.require_webhook_token/2` verifies via `Accounts.verify_webhook_token/1`

### Request pipeline

The `UserAuth` module provides plugs used in the router:

| Plug | Purpose |
|------|---------|
| `fetch_current_user` | Resolves user from session, Bearer token, or remember-me cookie |
| `require_authenticated_user` | Redirects to login (browser) or returns 401 (API) |
| `require_admin_user` | Redirects non-admins to dashboard |
| `require_webhook_token` | Validates webhook token from header or query param |
| `redirect_if_user_is_authenticated` | Prevents logged-in users from accessing login pages |

Token resolution priority in `fetch_current_user`:
1. Session token (from `user_token` session key) → verified as "session" context
2. Authorization header or `access_token` query param → base64-decoded, verified as "access" context
3. Remember-me cookie (signed) → verified as "session" context and injected into session

### LiveView authentication

Four `on_mount` hooks for LiveView sessions:
- `:mount_current_user` — Assigns user from session token (no redirect)
- `:ensure_authenticated` — Redirects to login if no user
- `:redirect_if_user_is_authenticated` — Redirects to dashboard if already logged in
- `:ensure_user_is_admin` — Redirects non-admins to dashboard

Logout broadcasts `"disconnect"` on the `live_socket_id` channel, disconnecting all LiveView sessions for the user.

### Authorization

`ExNVR.Authorization.authorize/3` implements five rules evaluated in order:

1. **Admins can do everything** — `:ok` for any resource/action
2. **No user management** — Regular users cannot access `:user` resource
3. **No system management** — Regular users cannot access `:system` resource
4. **Read-only** — Regular users can `:read` any other resource
5. **Deny by default** — Everything else returns `{:error, :unauthorized}`

Resources checked: `:device`, `:user`, `:system`, `:remote_storage`, `:trigger`, `:onvif`.

## Architecture

### Token types in database

All tokens are stored in the `users_tokens` table with a `context` field:

| Context | How created | Validity | Storage | Usage |
|---------|------------|----------|---------|-------|
| `"session"` | Browser login | 15 days | Raw bytes | Session cookie |
| `"access"` | `POST /api/users/login` | 2 days | Raw bytes | API Bearer token (base64-encoded for client) |
| `"webhook"` | Admin UI | No expiry | Raw bytes | Event ingestion auth |
| `"confirm"` | Registration email | 7 days | SHA-256 hash | Email confirmation |
| `"reset_password"` | Forgot password | 1 day | SHA-256 hash | Password reset link |
| `"change:*"` | Email change | 7 days | SHA-256 hash | Email change confirmation |

Email-derived tokens (confirm, reset, change) are hashed before storage — the raw token is sent via email. Session, access, and webhook tokens are stored as-is.

### User management (admin only)

REST API and LiveView pages for CRUD:

| Interface | Path | Notes |
|-----------|------|-------|
| `POST /api/users/login` | Public | Returns access token |
| `GET/POST/PUT/DELETE /api/users[/:id]` | Admin only | User CRUD |
| `/users/login` | Public | Browser login |
| `/users/settings` | Authenticated | Change password, email |
| `/users` | Admin | User list |
| `/users/:id` | Admin | User edit |

### Password requirements

- 8–72 characters
- At least one lowercase letter
- At least one uppercase letter
- At least one digit or punctuation character
- Bcrypt hashing (max 72 bytes input)
- Timing attack protection via `Bcrypt.no_user_verify/0`

## Data contracts

### Login API

```
POST /api/users/login
Content-Type: application/json

{"username": "user@example.com", "password": "secret123"}
```

Response: `{"access_token": "<base64_token>"}`

### Session cookie

Cookie name: `_ex_nvr_user_remember_me` (signed, max-age 15 days, SameSite=Lax).

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| Session max age | `UserAuth` | 15 days | Remember-me cookie lifetime |
| Access token validity | `UserToken` | 2 days | API token expiry |
| Webhook token validity | `UserToken` | None | Manually managed, no expiry |
| Confirmation token validity | `UserToken` | 7 days | Email confirmation link |
| Reset token validity | `UserToken` | 1 day | Password reset link |
| Mailer sender | `UserNotifier` | `contact@example.com` | Email from address |
