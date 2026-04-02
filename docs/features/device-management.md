---
name: device-management
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/devices.ex
  - ui/lib/ex_nvr/devices/**/*.ex
  - ui/lib/ex_nvr_web/controllers/api/device_controller.ex
  - ui/lib/ex_nvr_web/controllers/api/device_json.ex
  - ui/lib/ex_nvr_web/live/device_live.ex
  - ui/lib/ex_nvr_web/live/device_list_live.ex
  - ui/lib/ex_nvr_web/live/device_details_live.ex
  - ui/lib/ex_nvr_web/live/device_tabs/**/*.ex
  - ui/lib/ex_nvr/pipeline/source/**/*.ex
  - ui/lib/ex_nvr/authorization.ex
relates_to:
  concepts: [device, schedule]
  features: [onvif-discovery, video-recording, live-streaming, snapshot-upload]
---

## Overview

**Device management** is the admin feature for creating, configuring, monitoring, and controlling [devices](../domain/device.md) (IP cameras, video files, and webcams) in ExNVR. It provides both a web UI and a REST API for the full lifecycle: adding a device, configuring its recording and snapshot settings, monitoring its status and stream statistics, starting/stopping recording, and deleting it along with all associated data.

This feature is the administrative gateway to the system — without it, operators have no way to add cameras for ExNVR to record. It's closely integrated with [ONVIF discovery](onvif-discovery.md) (which can pre-populate device fields during creation) and the [video recording](video-recording.md) pipeline (which is started/stopped/restarted based on device configuration changes).

Only admin users can create, update, or delete devices. Regular users can view device details and recordings but cannot modify configurations.

## How it works

### Device creation

1. Admin navigates to `/devices/new` or sends `POST /api/devices`
2. The create form supports three device types:
   - **IP Camera** (`:ip`) — Requires RTSP stream URI, optional sub-stream and snapshot URIs
   - **File** (`:file`) — Upload an MP4 file for testing/demo; the file is copied to the storage directory
   - **Webcam** (`:webcam`) — Captures from a USB device at configured framerate/resolution
3. Storage configuration: select a disk volume (from `:disksup.get_disk_data/0`, excluding system partitions) or enter a custom path. Configure recording mode (always/never/on_event), full-drive threshold, and optional [schedule](../domain/schedule.md)
4. `Devices.create/1` inserts the device via `Ecto.Multi`, creates the directory tree on disk, copies the video file for `:file` type, and starts the device supervisor if the state is not `:stopped`
5. On success, redirects to the device list

The LiveView form (`DeviceLive`) pre-populates fields from flash params when coming from ONVIF discovery (model, URL, MAC address). It dynamically shows/hides form sections based on device type and recording mode. File uploads use Phoenix LiveView's `allow_upload` with a 1 GB limit and 4 MB chunk size.

### Device update

The update form is similar to creation but with restrictions:
- **Type is immutable** — the `update_changeset/2` does not accept `:type`
- **Name cannot be changed via UI** — the name input is not disabled, but the changeset allows it
- Config changes (stream URIs, settings, storage config) trigger a supervisor restart to pick up the new configuration

`Devices.update/2` handles supervisor lifecycle: if the device transitions between stopped and non-stopped states, the supervisor is started or stopped accordingly. If config changes are detected (via `Device.config_updated/2`), the supervisor is restarted.

### Device details page

`/devices/:id/details` — A tabbed detail view with live updates:

| Tab | Component | Purpose |
|-----|-----------|---------|
| Details | Inline | General info, hardware info, stream config, live snapshot preview |
| Recordings | `RecordingsListTab` | Paginated recording segments with filters, preview, download |
| Stats | `StatsTab` | Live stream statistics (bitrate, FPS, GOP, resolution) |
| Settings | `SettingsTab` | Storage config, snapshot config in read-only view |
| Events | `EventsListTab` | Device-scoped event browser |
| Triggers | `TriggersTab` | Toggle trigger associations |

The details page subscribes to `"device:#{device.id}"` PubSub topic for live device updates and `"stats:#{device.id}"` for stream statistics. It refreshes the snapshot preview image every 10 seconds when the device is streaming and has a snapshot URI.

**Start/Stop controls**: Admin users see Start/Stop buttons on the details page. These call `Devices.update_state/2` to transition the device state, which in turn starts or stops the pipeline supervisor.

### Device list

`/devices` — Table showing all devices with columns: ID (with copy button), type, name, vendor, timezone, state (with colored indicator), and active trigger count. Clicking a row navigates to the details page. Only admins see the "Add Device" button.

### Device deletion

`Devices.delete/1` stops the supervisor, then uses `Ecto.Multi` to delete all associated recordings, runs, and the device itself in a single transaction.

## Architecture

### REST API

All routes under `/api/devices` require authenticated user. Write operations require admin authorization.

| Method | Path | Auth | Action |
|--------|------|------|--------|
| `GET` | `/api/devices` | Any user | List all devices |
| `POST` | `/api/devices` | Admin | Create device |
| `GET` | `/api/devices/:id` | Any user | Show device |
| `PUT/PATCH` | `/api/devices/:id` | Admin | Update device |
| `DELETE` | `/api/devices/:id` | Admin | Delete device |

**JSON serialization** (`DeviceJSON`): Admin users receive the full device struct including sensitive config (stream URIs, credentials, storage config). Regular users receive only top-level fields (id, name, type, state, etc.).

### LiveView pages

| Path | Module | Access |
|------|--------|--------|
| `/devices` | `DeviceListLive` | Any user (Add button: admin only) |
| `/devices/new` | `DeviceLive` | Admin |
| `/devices/:id` | `DeviceLive` | Admin |
| `/devices/:id/details` | `DeviceDetailsLive` | Any user (Start/Stop: admin only) |

### Supervisor lifecycle

The `Devices` context manages the per-device supervision tree:

- **Create with non-stopped state** → start supervisor under `ExNVR.PipelineSupervisor`
- **Update state to stopped** → stop supervisor
- **Update state to non-stopped** → start supervisor
- **Config change while recording** → restart supervisor (stop + start)
- **Delete** → stop supervisor before database cleanup

The supervisor (`ExNVR.Devices.Supervisor`) uses `:rest_for_one` strategy and contains the main Membrane pipeline plus supporting GenServers (disk monitor, BIF generator, snapshot uploader, LPR puller, Unix socket server).

### Source elements

The pipeline source is chosen based on device type:

| Type | Source module | Notes |
|------|-------------|-------|
| `:ip` | `ExNVR.Pipeline.Source.RTSP` | Connects to `stream_uri`, optionally `sub_stream_uri` |
| `:file` | `ExNVR.Pipeline.Source.File` | Reads from uploaded MP4 file |
| `:webcam` | `ExNVR.Pipeline.Source.Webcam` | USB camera at configured framerate/resolution |

## Integrations

### ONVIF discovery flow

When a camera is discovered via [ONVIF](onvif-discovery.md), the discovery page can redirect to the device creation form with pre-populated fields (model, URL, MAC) passed through flash params. The `DeviceLive.mount/3` reads these from `socket.assigns.flash["device_params"]`.

### Disk detection

The create/edit form shows available disk volumes from `:disksup.get_disk_data/0`, filtering out system partitions (`/dev`, `/sys`, `/run`, `/tmp`, `/boot`). Each volume shows its total capacity in human-readable format (GiB/TiB). Users can toggle between volume selection and custom path input.

### PubSub

| Topic | Messages | Consumer |
|-------|----------|----------|
| `"device:#{id}"` | `{:device_updated, device}` | Details page (refreshes state) |
| `"stats:#{id}"` | `{:video_stats, {stream, stats}}` | Details page (stats tab) |

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `type` | Device | `:ip` | `:ip`, `:file`, `:webcam` — immutable after creation |
| `state` | Device | `:recording` | `:stopped`, `:streaming`, `:recording`, `:failed` |
| `timezone` | Device | `"UTC"` | Must be in `Tzdata.zone_list()` |
| `recording_mode` | `storage_config` | `:always` | `:always`, `:never`, `:on_event` |
| `address` | `storage_config` | — | Storage path, validated for write access |
| `full_drive_threshold` | `storage_config` | `95.0` | Percentage (0–100) |
| `full_drive_action` | `storage_config` | `:overwrite` | `:overwrite` or `:nothing` |
| `record_sub_stream` | `storage_config` | `:never` | `:never` or `:always` |
| `schedule` | `storage_config` | `nil` | Weekly recording schedule |
| `generate_bif` | `settings` | `true` | BIF thumbnail generation |
| `enable_lpr` | `settings` | `false` | LPR event polling |
| `snapshot_config` | Device | — | Upload interval, remote storage name, schedule |
