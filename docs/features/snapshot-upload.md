---
name: snapshot-upload
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/devices/snapshot_uploader.ex
  - ui/lib/ex_nvr/pipeline/output/socket.ex
  - ui/lib/ex_nvr/model/device/snapshot_config.ex
relates_to:
  concepts: [device, remote-storage, schedule]
  features: [remote-storage-sync, device-management]
---

## Overview

**Snapshot upload** periodically captures JPEG snapshots from a camera and uploads them to a configured [remote storage](../domain/remote-storage.md) backend (S3 or HTTP). It also provides a Unix socket interface for local consumers to receive decoded video frames in real time.

This feature serves two use cases:

1. **Remote snapshot archival** — The `SnapshotUploader` GenServer fetches a JPEG snapshot from the camera's HTTP snapshot endpoint at a configurable interval (5–3600 seconds) and uploads it to a named remote storage backend. This is controlled by the [device's](../domain/device.md) `snapshot_config`, which includes an enable flag, upload interval, remote storage name, and optional [schedule](../domain/schedule.md).

2. **Local socket streaming** — The `Output.Socket` Membrane sink decodes video frames from the pipeline's sub-stream (or main stream if no sub-stream), converts them to raw RGB24, and pushes them over Unix domain sockets to local consumers. This enables external processes (e.g., analytics engines) to receive decoded frames without going through HLS/WebRTC.

## How it works

### Snapshot upload flow

1. The `SnapshotUploader` GenServer starts as part of the per-device supervision tree (always started, but exits normally if conditions aren't met)
2. On init, sends `:init_config` to self
3. `handle_info(:init_config)` checks three conditions:
   - Device has a `snapshot_uri` configured (in `stream_config`)
   - `snapshot_config.enabled` is `true`
   - A [remote storage](../domain/remote-storage.md) with the configured name exists
4. If all conditions are met, builds upload opts from `RemoteStorage.build_opts/1` (S3 keys, HTTP credentials, URL) with a request timeout of `min(upload_interval, 30)` seconds
5. Every `upload_interval` seconds, checks if the current time falls within the configured schedule (using the device's timezone)
6. If scheduled, spawns an async task via `Task.Supervisor` to:
   - Fetch a JPEG snapshot from the camera via `Devices.fetch_snapshot/1`
   - Upload it via `Store.save_snapshot/5` (S3: `PUT` with key `ex_nvr/{device_id}/{YYYY}/{MM}/{DD}/{HH}/{MM}_{SS}_000.jpeg`; HTTP: multipart POST with metadata JSON + file)
7. The task has a yield timeout matching the configured timeout; if it doesn't complete, it's shut down

### Unix socket streaming

1. The `ExNVR.UnixSocketServer` (part of the device supervision tree, Unix OS only) listens for connections on a domain socket
2. When a client connects, sends `{:new_socket, socket}` to the pipeline
3. The pipeline creates an `Output.Socket` element linked to the sub-stream (or main stream) tee
4. `Output.Socket` decodes each keyframe + subsequent frames using `ExNVR.AV.Decoder` to raw RGB24
5. Sends a binary message per frame over each connected TCP socket with the format:
   ```
   [8 bytes: Unix timestamp ms][2 bytes: width][2 bytes: height][1 byte: channels (3)][payload: RGB24 data]
   ```
6. When all sockets close, notifies the parent with `:no_sockets`, and the pipeline removes the socket element
7. Waits for keyframe before starting to decode (skips non-keyframes until the first keyframe arrives)

## Architecture

### `ExNVR.Devices.SnapshotUploader`

A GenServer with `restart: :transient` — it starts once and exits normally if the snapshot config isn't usable (no snapshot URI, not enabled, or remote storage not found). This means it doesn't restart after a clean shutdown, preventing restart loops for unconfigured devices.

Key state:
- `device` — The device struct
- `remote_storage` — The resolved `RemoteStorage` struct (looked up by name from `snapshot_config.remote_storage`)
- `snapshot_config` — The device's parsed snapshot config with schedule
- `opts` — Upload opts (S3 keys, HTTP auth, URL, timeout)

Schedule checking uses the device's timezone: converts UTC now to local time, gets the day of week, and checks if the current time falls within any configured time interval for that day.

### `ExNVR.Pipeline.Output.Socket`

A Membrane `Sink` that receives H.264/H.265 access units, decodes them to RGB24 frames, and sends them over Unix domain sockets.

Key behaviors:
- Skips all buffers until the first keyframe arrives (`keyframe?` flag)
- No-ops when no sockets are connected (skips decoding entirely)
- Tracks `pts_to_datetime` mapping to associate decoded frames with their capture timestamps
- Flushes the decoder on stream format changes (codec switches)
- Removes closed sockets from the list on send failure
- Notifies parent when all sockets disconnect so the element can be removed from the pipeline

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `enabled` | `device.snapshot_config` | — | Master enable for snapshot uploading |
| `upload_interval` | `device.snapshot_config` | 30 | Seconds between uploads (5–3600) |
| `remote_storage` | `device.snapshot_config` | — | Name of the remote storage backend to use |
| `schedule` | `device.snapshot_config` | — | Weekly time-slot map (nil = always active) |
| `snapshot_uri` | `device.stream_config` | — | Camera HTTP endpoint for JPEG snapshots |
