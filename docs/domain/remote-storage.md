---
name: remote-storage
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/remote_storages/remote_storage.ex
  - ui/lib/ex_nvr/remote_storages.ex
  - ui/lib/ex_nvr/remote_storages/store.ex
  - ui/lib/ex_nvr/remote_storages/store/s3.ex
  - ui/lib/ex_nvr/remote_storages/store/http.ex
  - ui/lib/ex_nvr_web/controllers/api/remote_storage_controlller.ex
  - ui/lib/ex_nvr_web/controllers/api/remote_storage_json.ex
  - ui/lib/ex_nvr_web/live/remote_storage_list_live.ex
  - ui/lib/ex_nvr_web/live/remote_storage_live.ex
  - ui/lib/ex_nvr/devices/snapshot_uploader.ex
relates_to:
  concepts: [device, recording]
  features: [remote-storage-sync, snapshot-upload]
---

## Overview

A **Remote Storage** is a named, reusable configuration for an external storage backend where ExNVR can upload recordings and snapshots. It represents a destination — either an **S3-compatible object store** or an **HTTP endpoint** — that devices reference by name in their snapshot upload configuration.

Remote storages solve the problem of centralizing credentials and connection details for external storage. Rather than configuring S3 keys or HTTP auth on every device, admins create named remote storage entries (e.g. "production-s3", "backup-http") and then reference them by name in each [device's](device.md) snapshot configuration. This decouples the "where to upload" configuration from the "what to upload" configuration on each device.

The two concrete consumers of remote storage are:

1. **Snapshot upload** — The `ExNVR.Devices.SnapshotUploader` GenServer (part of each device's supervision tree) periodically fetches a JPEG snapshot from the camera and uploads it via the remote storage backend. The device's `snapshot_config.remote_storage` field is a name string that is looked up in the `remote_storages` table to resolve the actual backend.

2. **Recording upload** — The `ExNVR.RemoteStorages.Store` behaviour defines `save_recording/3` for uploading MP4 segments, though the recording sync feature uses it through a separate pipeline (see [remote-storage-sync](../features/remote-storage-sync.md)).

Remote storages are managed by admins through the Phoenix LiveView UI (`/remote-storages`) or the REST API. The API serialization intentionally strips sensitive configuration (S3 keys, HTTP credentials) from responses, returning only `id`, `name`, `type`, and `url`.

## Data model

### `ExNVR.RemoteStorage` (`ui/lib/ex_nvr/remote_storages/remote_storage.ex`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | integer (auto) | Primary key |
| `name` | `:string` | Unique name, used as the reference key from device configs |
| `type` | `Ecto.Enum` | `:s3` or `:http` |
| `url` | `:string` | S3 endpoint URL or HTTP upload URL |
| `s3_config` | embedded `S3Config` | S3 credentials (stored in `config` JSON column) |
| `http_config` | embedded `HttpConfig` | HTTP credentials (stored in `config` JSON column) |
| `inserted_at` | `:utc_datetime_usec` | Row creation time |
| `updated_at` | `:utc_datetime_usec` | Row update time |

Note: Both `s3_config` and `http_config` share the same database column (`config`) via `source: :config`. The schema populates the appropriate embedded schema based on the `type` field.

### Embedded schema: `S3Config`

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `bucket` | `:string` | — | S3 bucket name, required |
| `region` | `:string` | `"us-east-1"` | AWS region |
| `access_key_id` | `:string` | — | AWS access key, required |
| `secret_access_key` | `:string` | — | AWS secret key, required |

### Embedded schema: `HttpConfig`

| Field | Type | Notes |
|-------|------|-------|
| `username` | `:string` | For basic auth |
| `password` | `:string` | For basic auth |
| `token` | `:string` | For bearer token auth |

No fields are required — HTTP storage can be unauthenticated.

### `build_opts/1` — Runtime option construction

`RemoteStorage.build_opts/1` merges the S3 and HTTP config structs into a flat keyword list, enriched with:
- `:url` from the top-level field
- `:auth_type` — auto-detected: `:bearer` if a token is present, `:basic` if username+password, otherwise nil
- For S3 types: `:scheme`, `:host`, `:port` parsed from the URL (used by `ExAws`)

## API surface

### REST API

All routes under `/api/remote-storages` require authenticated user with admin permissions. Authorization is checked via `ExNVR.Authorization.authorize(user, :remote_storage, :any)`.

| Method | Path | Action |
|--------|------|--------|
| `GET` | `/api/remote-storages` | List all remote storages |
| `POST` | `/api/remote-storages` | Create remote storage |
| `GET` | `/api/remote-storages/:id` | Show remote storage |
| `PUT/PATCH` | `/api/remote-storages/:id` | Update remote storage |
| `DELETE` | `/api/remote-storages/:id` | Delete remote storage |

**JSON serialization** (`RemoteStorageJSON`): Only exposes `id`, `name`, `type`, and `url`. Sensitive fields (S3 keys, HTTP credentials) are never returned in API responses.

### LiveView pages

| Path | Module | Purpose |
|------|--------|---------|
| `/remote-storages` | `RemoteStorageListLive` | Table listing all remote storages with delete action |
| `/remote-storages/new` | `RemoteStorageLive` | Create form with dynamic config fields based on type |
| `/remote-storages/:id` | `RemoteStorageLive` | Update form (name and type are disabled) |

The create/edit form dynamically shows either S3 config fields (region, bucket, access key, secret key) or HTTP config fields (username, password, token) based on the selected type. Type selection triggers a `phx-change="update_type"` event to swap the config section.

## Business logic

### `ExNVR.RemoteStorages` context (`ui/lib/ex_nvr/remote_storages.ex`)

Standard CRUD operations:

- `create/1` — Inserts via `create_changeset/1`
- `update/2` — Updates via `update_changeset/2` (name and type cannot be changed)
- `delete/1` — Deletes the remote storage record
- `get/1`, `get!/1`, `get_by/1` — Fetches by id or arbitrary clauses
- `list/0` — Returns all remote storages ordered by `inserted_at`
- `count_remote_storages/0` — Returns the total count

### Store behaviour (`ExNVR.RemoteStorages.Store`)

Defines two callbacks that both S3 and HTTP backends implement:

- `save_recording(device, recording, opts)` — Upload an MP4 recording file
- `save_snapshot(device, snapshot, timestamp, opts)` — Upload a JPEG snapshot

The `Store` module dispatches to `S3` or `HTTP` based on the remote storage's `type` field.

### S3 backend (`ExNVR.RemoteStorages.Store.S3`)

Uses `ExAws.S3` for uploads:

- **Recordings**: Streamed upload via `S3.Upload.stream_file/1`. The S3 key is `{device_id}/{relative_path}` where the relative path preserves the local directory structure (`hi_quality/YYYY/MM/DD/timestamp.mp4`).
- **Snapshots**: Direct `S3.put_object/3` with `content_type: "image/jpeg"`. The key follows the pattern `ex_nvr/{device_id}/{YYYY}/{MM}/{DD}/{HH}/{MM}_{SS}_000.jpeg`.

### HTTP backend (`ExNVR.RemoteStorages.Store.HTTP`)

Uses `Req` for multipart POST uploads:

- Both recordings and snapshots are sent as `multipart/form-data` with two parts:
  1. A JSON `metadata` part containing `device_id` and either `start_date` (recordings) or `timestamp` (snapshots)
  2. A `file` part with the binary content
- Authentication is handled via `Req`'s `:auth` option: `:bearer` (token), `:basic` (username:password), or nil
- Success is any 2xx status code

## Storage

### Database

SQLite table `remote_storages` with columns: `id`, `name` (unique), `type`, `url`, `config` (JSON — holds either S3 or HTTP credentials), `inserted_at`, `updated_at`.

## Related concepts

- [device](device.md) — Devices reference remote storages by name in their `snapshot_config.remote_storage` field
- [recording](recording.md) — MP4 recording segments can be uploaded to remote storage

## Business rules

- **Name is immutable after creation** — The `update_changeset/2` only casts `:url`, not `:name` or `:type`. The LiveView form disables both fields on edit.
- **Type is immutable after creation** — Same as name; prevents breaking references and config schema mismatches.
- **Name is unique** — Enforced by a unique constraint on the `name` column. Devices reference remote storages by this name string.
- **URL is required for HTTP, optional for S3** — S3 backends can use the default AWS endpoint (no URL needed), while HTTP backends must specify where to POST.
- **URL validation** — When provided, the URL must have an `http` or `https` scheme and a non-empty host.
- **S3 requires bucket and keys** — The `S3Config` changeset requires `bucket`, `access_key_id`, and `secret_access_key`.
- **HTTP auth is optional** — All `HttpConfig` fields are optional. Auth type is auto-detected at runtime: bearer if token is set, basic if username+password are set, otherwise no auth.
- **API responses strip credentials** — `RemoteStorageJSON` only serializes `id`, `name`, `type`, `url` — never S3 keys or HTTP passwords.
- **Authorization** — Only admin users can access remote storage endpoints. The controller's `authorization_plug` checks `authorize(user, :remote_storage, :any)`, which grants access only to admins.
