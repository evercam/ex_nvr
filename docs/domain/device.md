---
name: device
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/model/device.ex
  - ui/lib/ex_nvr/model/device/**/*.ex
  - ui/lib/ex_nvr/devices.ex
  - ui/lib/ex_nvr/devices/**/*.ex
  - ui/lib/ex_nvr_web/controllers/api/device_controller.ex
  - ui/lib/ex_nvr_web/controllers/api/device_json.ex
  - ui/lib/ex_nvr_web/controllers/api/device_streaming_controller.ex
  - ui/lib/ex_nvr_web/live/device_live.ex
  - ui/lib/ex_nvr_web/live/device_list_live.ex
  - ui/lib/ex_nvr_web/live/device_details_live.ex
  - ui/lib/ex_nvr_web/live/device_tabs/**/*.ex
  - ui/lib/ex_nvr/authorization.ex
relates_to:
  concepts: [recording, run, schedule, event, lpr-event, remote-storage]
  features: [device-management, video-recording, live-streaming, onvif-discovery, snapshot-upload, bif-thumbnails]
---

## Overview

A **Device** is the central entity in ExNVR — it represents a video source that the system records, monitors, and streams from. In most deployments this is an IP camera accessed via RTSP, but the system also supports local video files (for testing/demo) and USB webcams.

Every other subsystem in ExNVR revolves around the device: the Membrane recording pipeline is started per-device, recordings and runs are scoped to a device, events (generic and LPR) are associated with a device, snapshots are fetched from a device, and BIF thumbnails are generated per-device. Without the device entity, nothing in ExNVR has a source to operate on.

Devices have a **state machine** with four states: `:stopped`, `:streaming`, `:recording`, and `:failed`. When a device is not stopped, ExNVR starts a per-device supervision tree (`ExNVR.Devices.Supervisor`) under the `ExNVR.PipelineSupervisor` dynamic supervisor. This tree contains the main Membrane pipeline, disk monitor, BIF generator, snapshot uploader, and optionally an LPR event puller and Unix socket server.

Three camera vendors have first-class HTTP client support: **Hikvision**, **Milesight**, and **AXIS**. These vendor-specific clients can fetch device info, stream profiles, and LPR events directly from the camera's HTTP API. All IP cameras also support **ONVIF** for discovery, auto-configuration, stream profile management, and recording enumeration.

Devices are managed by admins through the Phoenix LiveView UI (`/devices`) or the REST API. Regular users can view device details but cannot create, update, or delete them.

## Data model

### `ExNVR.Model.Device` (`ui/lib/ex_nvr/model/device.ex`)

Primary key: `:id` (`:binary_id`, auto-generated UUID).

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `name` | `:string` | — | Human-readable name, required |
| `type` | `Ecto.Enum` | `:ip` | `:ip`, `:file`, or `:webcam` |
| `timezone` | `:string` | `"UTC"` | Validated against `Tzdata.zone_list()` |
| `state` | `Ecto.Enum` | `:recording` | `:stopped`, `:streaming`, `:recording`, `:failed` |
| `vendor` | `:string` | — | Camera manufacturer string (e.g. `"HIKVISION"`) |
| `mac` | `:string` | — | MAC address, used for ONVIF discovery matching |
| `url` | `:string` | — | Base HTTP URL of the camera |
| `model` | `:string` | — | Camera model string |

### Embedded schemas

**`Device.Credentials`** — username/password pair for RTSP and HTTP authentication.

**`Device.StreamConfig`** — RTSP stream URIs, snapshot URIs, ONVIF profile tokens, and file-type settings:
- `stream_uri` (required for `:ip` type, validated as RTSP URI)
- `sub_stream_uri`, `sub_snapshot_uri`, `sub_profile_token` — optional sub-stream configuration
- `third_stream_uri`, `third_profile_token` — optional third stream
- `snapshot_uri`, `sub_snapshot_uri` — HTTP snapshot endpoints
- `filename`, `temporary_path`, `duration` — for `:file` type devices
- `framerate` (default `8.0`), `resolution` — for `:webcam` type

**`Device.Settings`** (`ui/lib/ex_nvr/model/device.ex:144`):
- `generate_bif` (default `true`) — whether to generate BIF thumbnails for video scrubbing
- `enable_lpr` (default `false`) — whether to pull LPR events from the camera's HTTP API

**`Device.StorageConfig`** (`ui/lib/ex_nvr/model/device/storage_config.ex`):
- `recording_mode` — `:never`, `:always`, or `:on_event` (default `:always`)
- `address` — filesystem path for storing recordings; validated for write access on creation
- `full_drive_threshold` (default `95.0`) — percentage at which the drive is considered full
- `full_drive_action` — `:nothing` or `:overwrite` (default `:overwrite`)
- `record_sub_stream` — `:never` or `:always` (default `:never`)
- `schedule` — weekly recording [schedule](schedule.md) map

**`Device.SnapshotConfig`** (`ui/lib/ex_nvr/model/device/snapshot_config.ex`):
- `enabled` — whether periodic snapshot uploading is active
- `upload_interval` (default `30`, range 5–3600 seconds)
- `remote_storage` — name of the [remote storage](remote-storage.md) backend to upload to
- `schedule` — weekly upload [schedule](schedule.md) map

### Directory layout

Each device stores data under `{storage_address}/ex_nvr/{device_id}/`:

```
{address}/ex_nvr/{device_id}/
├── hi_quality/          # Main stream recordings
├── lo_quality/          # Sub-stream recordings
├── bif/                 # BIF thumbnail files
└── thumbnails/
    ├── bif/             # BIF source thumbnails
    └── lpr/             # LPR event plate images
```

## API surface

### REST API

All routes are under `/api/` and require authentication.

| Method | Path | Action | Auth |
|--------|------|--------|------|
| `GET` | `/api/devices` | List all devices | any user |
| `POST` | `/api/devices` | Create device | admin only |
| `GET` | `/api/devices/:id` | Show device | any user |
| `PUT/PATCH` | `/api/devices/:id` | Update device | admin only |
| `DELETE` | `/api/devices/:id` | Delete device | admin only |
| `GET` | `/api/devices/:id/hls/index.m3u8` | Start HLS stream | any user |
| `GET` | `/api/devices/:id/hls/*path` | Fetch HLS segment | any user |
| `GET` | `/api/devices/:id/snapshot` | Fetch live or recorded snapshot | any user |
| `GET` | `/api/devices/:id/footage` | Download MP4 footage clip | any user |
| `GET` | `/api/devices/:id/bif/:hour` | Fetch BIF thumbnail file | any user |

**JSON serialization** (`ExNVRWeb.API.DeviceJSON`): admin users receive the full device struct including `stream_config`, `credentials`, `settings`, `snapshot_config`, and `storage_config`. Regular users receive only top-level fields (id, name, type, state, etc.) — sensitive configuration is stripped.

### LiveView pages

| Path | Module | Purpose |
|------|--------|---------|
| `/devices` | `DeviceListLive` | Table of all devices with state indicators and trigger counts |
| `/devices/new` | `DeviceLive` | Create form with file upload support |
| `/devices/:id` | `DeviceLive` | Edit form |
| `/devices/:id/details` | `DeviceDetailsLive` | Tabbed detail view: Details, Recordings, Stats, Settings, Events, Triggers |

The details page subscribes to `"device:#{device.id}"` PubSub topic to receive live updates and refreshes the snapshot image every 10 seconds when the device is streaming and has a snapshot URI configured.

## Business logic

### `ExNVR.Devices` context (`ui/lib/ex_nvr/devices.ex`)

**CRUD operations:**

- `create/1` — Inserts the device via `Ecto.Multi`, creates the directory tree on disk, copies the video file for `:file` type devices, and starts the device supervisor if the state is not `:stopped`.
- `update/2` — Updates the device, creates any missing directories, manages the supervisor lifecycle (start/stop/restart based on state and config changes), and broadcasts `{:device_updated, device}` on the `"device:#{id}"` PubSub topic.
- `delete/1` — Stops the supervisor, then deletes all associated [recordings](recording.md), [runs](run.md), and the device itself in a multi-transaction.
- `update_state/2` — Convenience wrapper around `update/2` for state transitions.
- `list/1` — Accepts filter params (`:state`, `:type`, `:mac`) and returns devices ordered by `inserted_at`.

**Supervisor lifecycle** (`start_or_stop_supervisor/2`):

The supervisor management logic handles several transitions:
- New device with non-stopped state → start supervisor
- Device deleted → stop supervisor
- State changed to stopped → stop supervisor
- State changed to non-stopped → start supervisor
- Config changed while recording → restart supervisor (stop + start)

**Vendor-specific operations:**

- `device_info/1` — Fetches camera hardware info via the vendor HTTP client
- `stream_profiles/1` — Fetches available stream profiles
- `fetch_lpr_event/2` — Fetches LPR events from the camera (supports timestamp-based pagination)
- `fetch_snapshot/1` — Fetches a live JPEG snapshot from the camera's `snapshot_uri`
- `summary/0` — Async-streams over all devices, collecting state, stream stats, and ONVIF configuration

## System integration

### Per-device supervision tree (`ExNVR.Devices.Supervisor`)

Started as a child of `ExNVR.PipelineSupervisor` (a `DynamicSupervisor`). Uses `:rest_for_one` strategy with a high restart limit (10,000). The supervisor name is the device's UUID atom.

Children vary by recording mode and settings:

| Child | When started | Purpose |
|-------|-------------|---------|
| `ExNVR.Pipelines.Main` | Always | Membrane pipeline for RTSP ingest, recording, and live output |
| `ExNVR.DiskMonitor` | `recording_mode != :never` | Monitors disk usage against `full_drive_threshold` |
| `ExNVR.BIF.GeneratorServer` | `recording_mode != :never` | Generates BIF thumbnail files hourly |
| `ExNVR.Devices.SnapshotUploader` | Always | Periodic snapshot capture and upload to [remote storage](remote-storage.md) |
| `ExNVR.Devices.LPREventPuller` | `enable_lpr == true` and HTTP URL present | Polls camera for [LPR events](lpr-event.md) every 10 seconds |
| `ExNVR.UnixSocketServer` | Unix OS only | Exposes a Unix socket for local snapshot consumers |

### ONVIF integration (`ExNVR.Devices.Onvif`)

- `discover/1` — Probes the network for ONVIF-compatible devices, filtering out link-local addresses
- `auto_configure/1` — Vendor-aware profile setup: AXIS cameras get dedicated `ex_nvr_main`/`ex_nvr_sub` profiles created; other vendors configure the first two existing profiles. Main stream targets H.265 at 3072 kbps; sub-stream targets H.264 at 572 kbps.
- `all_config/1` — Returns stream profiles, camera information (manufacturer, model, serial, firmware), local date/time, and on-camera recordings

### Camera HTTP clients

The `ExNVR.Devices.Cameras.HttpClient` behaviour defines three optional callbacks:
- `fetch_lpr_event/2` — vendor-specific LPR event retrieval
- `device_info/2` — returns `DeviceInfo` struct
- `stream_profiles/2` — returns list of `StreamProfile` structs

Implementations: `Hik` (Hikvision), `Milesight`, `Axis`.

### PubSub topics

- `"device:#{device_id}"` — broadcasts `{:device_updated, device}` on update
- `"stats:#{device_id}"` — receives `{:video_stats, {stream, stats}}` from the pipeline

## Storage

### Database

SQLite table `devices` with embedded JSON columns for `credentials` (`:credentials`), `stream_config` (`:config`), `settings`, `storage_config`, and `snapshot_config`.

Queries use the `Device.filter/2` function for filtering by `:state` (single atom or list), `:type`, and `:mac`.

### File system

Recording files are stored under the `storage_config.address` path. The `create_device_directories/1` function ensures the full directory tree exists (`hi_quality`, `lo_quality`, `bif`, `thumbnails/bif`, `thumbnails/lpr`). For `:file` type devices, the source video file is copied from `temporary_path` into the device's base directory on creation.

## Related concepts

- [recording](recording.md) — Video segments stored by the device's pipeline
- [run](run.md) — Recording sessions that group contiguous recordings
- [schedule](schedule.md) — Weekly time-slot schedules for recording and snapshots
- [event](event.md) — Generic device events ingested via webhook
- [lpr-event](lpr-event.md) — License plate recognition events pulled from camera or ingested via API
- [remote-storage](remote-storage.md) — S3/HTTP backends for snapshot and recording uploads

## Business rules

- **Type is immutable after creation** — the `update_changeset/2` does not accept `:type` in its cast fields; only `create_changeset/2` does.
- **Storage address requires write access** — on creation, the `StorageConfig.changeset/2` validates that `File.stat/1` returns `:read_write` for the address path.
- **Storage address is required when recording** — if `recording_mode` is not `:never`, the `address` field is required.
- **Snapshot upload validation** — when `enabled` is true, `upload_interval` (5–3600s) and `remote_storage` name are required; the schedule is validated via `Schedule.validate/1`.
- **Authorization** — admins can perform all CRUD operations. Regular users are limited to `:read` actions on devices; create/update/delete return `{:error, :unauthorized}`.
- **Config change detection** — `Device.config_updated/2` compares `stream_config`, `settings`, and `storage_config` between old and new device structs to decide whether the supervisor needs a restart.
- **Streaming state helpers** — `recording?/1` returns true for any non-stopped state (the pipeline is running). `streaming?/1` returns true only for `:recording` and `:streaming` states (media is flowing).
