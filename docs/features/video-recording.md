---
name: video-recording
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/pipelines/main.ex
  - ui/lib/ex_nvr/pipelines/main/**/*.ex
  - ui/lib/ex_nvr/pipeline/output/storage.ex
  - ui/lib/ex_nvr/pipeline/output/storage/**/*.ex
  - ui/lib/ex_nvr/pipeline/output/thumbnailer.ex
  - ui/lib/ex_nvr/pipeline/source/rtsp.ex
  - ui/lib/ex_nvr/pipeline/source/file.ex
  - ui/lib/ex_nvr/pipeline/source/webcam.ex
  - ui/lib/ex_nvr/pipeline/storage_monitor.ex
  - ui/lib/ex_nvr/elements/recording.ex
  - ui/lib/ex_nvr/recordings.ex
  - ui/lib/ex_nvr/recordings/**/*.ex
  - ui/lib/ex_nvr/disk_monitor.ex
  - ui/lib/ex_nvr_web/controllers/api/recording_controller.ex
  - ui/lib/ex_nvr_web/live/recordings_list_live.ex
relates_to:
  concepts: [device, recording, run, schedule]
  features: [live-streaming, playback, remote-storage-sync, bif-thumbnails]
---

## Overview

**Video recording** is the core feature of ExNVR — it continuously captures video streams from IP cameras, files, or webcams and stores them as MP4 segments on the local filesystem. Without recording, ExNVR would be a live viewer with no history.

The feature is built on the **Membrane Framework**, an Elixir media processing toolkit. Each [device](../domain/device.md) gets its own Membrane pipeline (`ExNVR.Pipelines.Main`) that ingests media from a source (RTSP, file, or webcam), splits it into fixed-duration segments (default 60 seconds), and writes each segment as a self-contained MP4 file. The pipeline also feeds other features: [live streaming](live-streaming.md) (HLS + WebRTC), [BIF thumbnail](bif-thumbnails.md) generation, and live snapshot capture.

Recording is governed by three controls:
1. **Recording mode** — `:always`, `:never`, or `:on_event` (configured per-device in `storage_config`)
2. **[Schedule](../domain/schedule.md)** — Optional weekly time-slot map that restricts when recording is active
3. **Disk management** — The `DiskMonitor` automatically deletes the oldest recordings when disk usage exceeds the configured threshold

The pipeline manages its own lifecycle, transitioning the device through states: `:failed` → `:streaming` (connected but not yet recording) → `:recording` (segments being written). These state transitions are reported via telemetry and PubSub.

## How it works

### End-to-end recording flow

1. **Device startup**: When a device with a non-stopped state is created or updated, `ExNVR.Devices` starts its supervision tree under `ExNVR.PipelineSupervisor`
2. **Pipeline init**: `ExNVR.Pipelines.Main` starts, deactivates any stale [runs](../domain/run.md), sets device state to `:failed` (or `:streaming` for file type), and spawns the appropriate source element
3. **Source connects**: The RTSP/file/webcam source establishes a media connection and notifies the pipeline about available tracks (main stream, optionally sub-stream)
4. **Pipeline builds**: On receiving track notifications, the pipeline constructs the output graph — tee elements fan out to: storage sink, HLS sink, WebRTC output, snapshot bufferer, stats reporter, and optionally thumbnailer
5. **StorageMonitor decides**: The `StorageMonitor` GenServer checks directory writability and schedule, then sends `{:storage_monitor, :record?, true/false}` to the pipeline
6. **Recording starts**: When `record?` is `true`, the pipeline spawns the `Output.Storage` sink(s). The storage sink waits for the first keyframe, opens an MP4 file, and starts writing
7. **Segment splitting**: When the current segment exceeds the target duration (60s) and a keyframe arrives, the file is finalized, the [recording](../domain/recording.md) row is created in the database, and a new file is opened
8. **Continuous operation**: This cycle repeats indefinitely. On disconnection, the current segment is finalized, the run is marked inactive, and the source attempts to reconnect

### Recording vs streaming states

The pipeline distinguishes between being connected (streaming) and actively writing to disk (recording):
- **`:streaming`** — Media is flowing from the source. HLS, WebRTC, and snapshots work, but no segments are being written.
- **`:recording`** — Media is flowing AND the storage sink is writing segments. The device transitions from `:streaming` to `:recording` when the first segment's `new_segment` notification arrives.

This split is important because recording can be disabled (via schedule, manual stop, or `recording_mode: :never`) while the camera stream continues serving live viewers.

## Architecture

### Pipeline topology (`ExNVR.Pipelines.Main`)

```
Source (RTSP/File/Webcam)
  ├── main_stream → Tee
  │     ├── Output.Storage (main)     → MP4 segments
  │     ├── Output.HLS (main)         → Live HLS playlist
  │     ├── Output.WebRTC (main)      → WebRTC peers
  │     ├── CVSBufferer               → Live snapshot capture
  │     └── VideoStreamStatReporter   → Stream stats → PubSub
  │
  └── sub_stream → Tee
        ├── Output.Storage (sub)      → MP4 segments (if record_sub_stream: :always)
        ├── Output.HLS (sub)          → Live HLS playlist
        ├── Output.WebRTC (sub)       → WebRTC peers
        ├── Thumbnailer               → BIF source thumbnails (if generate_bif: true)
        └── VideoStreamStatReporter   → Stream stats → PubSub
```

The pipeline uses Membrane `Tee` elements to fan out each stream to multiple sinks. Storage sinks are dynamically added/removed when the `StorageMonitor` toggles recording.

### Source elements

| Source | Module | Device type | Notes |
|--------|--------|-------------|-------|
| RTSP | `ExNVR.Pipeline.Source.RTSP` | `:ip` | Connects to `stream_uri`, optionally `sub_stream_uri` |
| File | `ExNVR.Pipeline.Source.File` | `:file` | Reads from a local MP4 file (loops for testing) |
| Webcam | `ExNVR.Pipeline.Source.Webcam` | `:webcam` | Captures from USB device at configured framerate/resolution |

### Storage sink (`ExNVR.Pipeline.Output.Storage`)

A Membrane `Sink` that receives H.264/H.265 access units and writes them as MP4 segments:

- **Segment lifecycle**: Waits for first keyframe → opens file → writes samples → on next keyframe after target duration → finalizes → creates DB record → opens new file
- **Timestamp correction**: When `correct_timestamp: true`, adjusts segment end dates toward the wall clock, clamped to ±30ms. Drifts exceeding 30 seconds are treated as time discontinuities (e.g. NTP jumps)
- **First segment handling**: The first segment's start date is retroactively adjusted to account for camera buffering, and the file is renamed on disk
- **Run management**: Creates a new `Run` when recording starts or after a discontinuity. Tracks `disk_serial` resolved from the storage mountpoint. Runs are marked `active: false` on discontinuity
- **Discontinuity handling**: Stream disconnections, codec changes, and end-of-stream events finalize the current segment and end the run
- **Parameter set extraction**: On each keyframe, SPS/PPS (H.264) or VPS/SPS/PPS (H.265) are extracted from the access unit and stored in the track's `priv_data` for the MP4 container
- **Telemetry**: Emits `[:ex_nvr, :recordings, :stop]` with duration and size metrics

### StorageMonitor (`ExNVR.Pipeline.StorageMonitor`)

A GenServer child of the pipeline that determines whether recording should be active:

- Checks directory writability on startup (polls every 5s if not writable)
- If a [schedule](../domain/schedule.md) is configured, polls `Schedule.scheduled?/2` every 5s in the device's timezone
- Sends `{:storage_monitor, :record?, boolean}` to the pipeline, deduplicating unchanged values
- Supports `pause/1` and `resume/1` for manual recording control

### DiskMonitor (`ExNVR.DiskMonitor`)

A GenServer in the per-device supervision tree (when `recording_mode != :never`):

- Polls disk usage every 1 minute via `:disksup.get_disk_info/0`
- When usage exceeds `full_drive_threshold` (default 95%) for 5 consecutive ticks, calls `Recordings.delete_oldest_recordings/2` to delete up to 30 oldest recordings
- Only active when `full_drive_action` is not `:nothing`

### Supervision tree

The per-device supervisor (`ExNVR.Devices.Supervisor`) uses `:rest_for_one` strategy:

1. `ExNVR.Pipelines.Main` — The Membrane pipeline (always started)
2. `ExNVR.DiskMonitor` — Disk usage monitoring (when `recording_mode != :never`)
3. `ExNVR.BIF.GeneratorServer` — BIF file generation (when `recording_mode != :never`)
4. `ExNVR.Devices.SnapshotUploader` — Periodic snapshot upload (always started)
5. `ExNVR.Devices.LPREventPuller` — LPR event polling (when `enable_lpr` and URL present)
6. `ExNVR.UnixSocketServer` — Unix socket for local snapshot consumers (Unix OS only)

## Integrations

### RTSP

The primary ingest protocol. `ExNVR.Pipeline.Source.RTSP` connects to the device's `stream_uri` (and optionally `sub_stream_uri`) using the Membrane RTSP plugin. Supports H.264 and H.265 codecs only. On connection loss, notifies the pipeline via `{:connection_lost, :main_stream}`, which sets the device state to `:failed`. Reconnection is handled by the source element.

### WebRTC

Both main and sub streams are available for WebRTC peer connections via `Output.WebRTC`. ICE servers are configured via the `:ice_servers` application config (falls back to Google STUN). Peers are added/removed dynamically via `Main.add_webrtc_peer/2` and `Main.forward_peer_message/3`.

### Telemetry

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:ex_nvr, :main_pipeline, :state]` | — | `device_id`, `old_state`, `new_state` |
| `[:ex_nvr, :main_pipeline, :terminate]` | `system_time` | `device_id` |
| `[:ex_nvr, :recordings, :stop]` | `duration` (ms), `size` (bytes) | `device_id`, `stream` |

## Data contracts

### Segment on disk

Each segment is a self-contained MP4 file with `fast_start: true` (moov atom at the beginning). Contains a single video track with parameter sets in `priv_data`. Named by Unix microsecond timestamp: `{unix_us}.mp4`.

Path: `{storage_address}/ex_nvr/{device_id}/{hi_quality|lo_quality}/{YYYY}/{MM}/{DD}/{unix_us}.mp4`

### Database records

Each finalized segment creates:
- A `Recording` row: `start_date`, `end_date`, `filename`, `stream`, `device_id`, `run_id`
- A `Run` upsert: extends `end_date`, or creates a new run after discontinuity

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `recording_mode` | `device.storage_config` | `:always` | `:always`, `:never`, or `:on_event` |
| `address` | `device.storage_config` | — | Filesystem path for recordings (must be writable) |
| `full_drive_threshold` | `device.storage_config` | `95.0` | Percentage at which disk cleanup triggers |
| `full_drive_action` | `device.storage_config` | `:overwrite` | `:overwrite` (delete oldest) or `:nothing` |
| `record_sub_stream` | `device.storage_config` | `:never` | `:always` to record both streams |
| `schedule` | `device.storage_config` | `nil` | Weekly time-slot map (nil = always record) |
| `generate_bif` | `device.settings` | `true` | Whether to generate BIF thumbnails from sub-stream |
| `segment_duration` | Pipeline option | 60s | Target segment duration (actual may be slightly longer due to keyframe alignment) |
| `:ice_servers` | App config | Google STUN | JSON list of ICE/TURN servers for WebRTC |
