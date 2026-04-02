---
name: remote-storage-sync
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/remote_storages.ex
  - ui/lib/ex_nvr/remote_storages/remote_storage.ex
  - ui/lib/ex_nvr/remote_storages/store.ex
  - ui/lib/ex_nvr/remote_storages/store/s3.ex
  - ui/lib/ex_nvr/remote_storages/store/http.ex
  - ui/lib/ex_nvr_web/controllers/api/remote_storage_controlller.ex
  - ui/lib/ex_nvr_web/controllers/api/remote_storage_json.ex
  - ui/lib/ex_nvr_web/live/remote_storage_list_live.ex
  - ui/lib/ex_nvr_web/live/remote_storage_live.ex
  - ui/lib/ex_nvr/devices/snapshot_uploader.ex
relates_to:
  concepts: [remote-storage, recording, device]
  features: [video-recording, snapshot-upload]
---

## Overview

**Remote storage sync** is the mechanism that uploads media from ExNVR to external storage backends — either **S3-compatible object stores** or **HTTP endpoints**. It provides the transport layer that [snapshot upload](snapshot-upload.md) and (in the future) recording upload use to move data off the local filesystem.

The feature consists of:
1. **[Remote storage](../domain/remote-storage.md) configuration** — Named, reusable backend definitions (S3 bucket + credentials, or HTTP endpoint + auth) managed by admins
2. **Store behaviour and implementations** — A pluggable `ExNVR.RemoteStorages.Store` behaviour with `S3` and `HTTP` backends
3. **Snapshot syncing** — Currently the primary consumer, via the `SnapshotUploader` (see [snapshot-upload](snapshot-upload.md))
4. **Recording syncing** — The `Store` behaviour defines `save_recording/3` for both backends, providing the interface for future recording upload functionality

Without this feature, all media would remain on the local disk with no off-site backup or integration with cloud storage platforms.

## How it works

### S3 backend (`ExNVR.RemoteStorages.Store.S3`)

Uses `ExAws.S3` for uploads:

**Snapshots**: Direct `S3.put_object/3` with `content_type: "image/jpeg"`. Key pattern:
```
ex_nvr/{device_id}/{YYYY}/{MM}/{DD}/{HH}/{MM}_{SS}_000.jpeg
```

**Recordings**: Streamed upload via `S3.Upload.stream_file/1` for large MP4 files. Key pattern:
```
{device_id}/{relative_path_from_device_base_dir}
```
This preserves the local directory structure (`hi_quality/YYYY/MM/DD/timestamp.mp4`).

Both operations use `ExAws.request/2` with opts built from the remote storage's `S3Config` (bucket, region, access key, secret key) plus the parsed URL (scheme, host, port for S3-compatible endpoints like MinIO).

### HTTP backend (`ExNVR.RemoteStorages.Store.HTTP`)

Uses `Req` for multipart POST uploads:

Both snapshots and recordings are sent as `multipart/form-data` with two parts:
1. **`metadata`** — JSON part with `device_id` and either `start_date` (recordings) or `timestamp` (snapshots)
2. **`file`** — Binary content with appropriate filename

Authentication is auto-detected from the HTTP config:
- If `token` is set → Bearer auth
- If `username` + `password` are set → Basic auth
- Otherwise → no auth

Success is any 2xx status code.

### Runtime option construction

`RemoteStorage.build_opts/1` merges the S3 and HTTP embedded configs into a flat keyword list enriched with:
- `:url` from the top-level field
- `:auth_type` (`:bearer`, `:basic`, or nil) — auto-detected from credentials
- For S3: `:scheme`, `:host`, `:port` parsed from the URL (needed by `ExAws`)

## Architecture

### Store behaviour (`ExNVR.RemoteStorages.Store`)

Defines two callbacks:
- `save_recording(device, recording, opts)` — Upload an MP4 [recording](../domain/recording.md) file
- `save_snapshot(device, snapshot_binary, timestamp, opts)` — Upload a JPEG snapshot

The `Store` module provides a `save_snapshot/5` convenience function that dispatches to `S3` or `HTTP` based on the remote storage's `type` field.

### Management UI and API

Remote storages are managed through:

| Interface | Path | Notes |
|-----------|------|-------|
| REST API | `/api/remote-storages` | Full CRUD, admin only |
| LiveView | `/remote-storages` | List with delete |
| LiveView | `/remote-storages/new` | Create form |
| LiveView | `/remote-storages/:id` | Edit form (name/type locked) |

The create/edit form dynamically switches between S3 config fields (region, bucket, access key, secret key) and HTTP config fields (username, password, token) based on the selected type.

API responses strip sensitive fields — `RemoteStorageJSON` only serializes `id`, `name`, `type`, `url`.

### Consumer: Snapshot uploader

The `SnapshotUploader` GenServer resolves a remote storage by name from the [device's](../domain/device.md) `snapshot_config.remote_storage` field, builds opts via `RemoteStorage.build_opts/1`, and calls `Store.save_snapshot/5` on each upload cycle.

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `type` | `remote_storages.type` | — | `:s3` or `:http` — immutable after creation |
| `name` | `remote_storages.name` | — | Unique reference key — immutable after creation |
| `url` | `remote_storages.url` | — | S3 endpoint or HTTP upload URL |
| `bucket` | `s3_config` | — | S3 bucket name (required for S3) |
| `region` | `s3_config` | `"us-east-1"` | AWS region |
| `access_key_id` | `s3_config` | — | AWS access key (required for S3) |
| `secret_access_key` | `s3_config` | — | AWS secret key (required for S3) |
| `username` | `http_config` | — | For HTTP basic auth (optional) |
| `password` | `http_config` | — | For HTTP basic auth (optional) |
| `token` | `http_config` | — | For HTTP bearer auth (optional) |
