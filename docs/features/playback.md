---
name: playback
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/pipelines/hls_playback.ex
  - ui/lib/ex_nvr/elements/recording.ex
  - ui/lib/ex_nvr/elements/realtimer.ex
  - ui/lib/ex_nvr/hls/processor.ex
  - ui/lib/ex_nvr/recordings/concatenater.ex
  - ui/lib/ex_nvr/recordings/video_assembler.ex
  - ui/lib/ex_nvr_web/controllers/api/device_streaming_controller.ex
  - ui/lib/ex_nvr_web/hls_streaming_monitor.ex
  - ui/assets/vue/Viewer.vue
  - ui/assets/vue/Timeline.vue
relates_to:
  concepts: [device, recording, run]
  features: [video-recording, live-streaming, bif-thumbnails]
---

## Overview

**Playback** allows users to watch previously recorded footage by navigating a timeline and streaming stored video segments through HLS. It also supports extracting single-frame snapshots and downloading MP4 footage clips from recordings.

The feature bridges the gap between stored [recordings](../domain/recording.md) on disk and the browser-based video player. When a user clicks a point on the timeline, the system spawns a dedicated Membrane pipeline (`HlsPlayback`) that reads MP4 segments from disk via the `Concatenater`, optionally transcodes them to a lower resolution, paces them at real-time speed via `Realtimer`, and writes HLS playlists to a temporary directory. The browser's HLS.js player then fetches these playlists and segments through the same streaming controller used for [live streaming](live-streaming.md).

The UI consists of a **Viewer** component (Vue) with an HLS video player and a **Timeline** component showing green bars for periods where footage exists (based on [runs](../domain/run.md)). Clicking anywhere on the timeline triggers playback from that timestamp. A "LIVE" button switches back to the live stream.

## How it works

### Playback flow

1. User clicks a timestamp on the `Timeline` component
2. The LiveView emits a `load-recording` event with the selected timestamp
3. The controller receives `GET /api/devices/:id/hls/index.m3u8?pos=<timestamp>&stream=<stream>&duration=<seconds>`
4. `DeviceStreamingController.start_hls_pipeline/3` determines the stream type (`:high`, `:low`, or `:auto` — auto picks low if available, falls back to high)
5. An `HlsPlayback` pipeline is started with the device, start date, stream, duration, and optional resolution
6. The pipeline creates a `Recording` source element that opens the `Concatenater` at the requested timestamp
7. `start_streaming/1` is called, which completes the pipeline setup
8. The `Recording` source reads samples from consecutive MP4 files, feeds them through `Realtimer` (real-time pacing), optionally through `Transcoder` (downscaling), and into `Output.HLS`
9. When the first HLS segment is created, the pipeline notifies the controller, which reads the master manifest, injects query parameters, and returns it
10. The `HlsStreamingMonitor` tracks the session — if no manifest request arrives for 45 seconds, it calls `HlsPlayback.stop_streaming/1` to shut down the pipeline

### Snapshot extraction

`GET /api/devices/:id/snapshot?time=<timestamp>&method=<before|precise>&stream=<high|low>`

1. Finds the recording that contains the requested timestamp via `Recordings.get_recordings_between/5`
2. Opens the MP4 file with `ExMP4.Reader` and seeks to the timestamp
3. Two extraction methods:
   - `:before` — Returns the nearest preceding keyframe (fast, no decoding)
   - `:precise` — Decodes from the preceding keyframe up to the exact requested frame (slower but frame-accurate)
4. Returns JPEG with an `x-timestamp` header

### Footage download

`GET /api/devices/:id/footage?start_date=<timestamp>&end_date=<timestamp>&duration=<seconds>&stream=<high|low>`

1. Validates that either `end_date` or `duration` is provided (max 2 hours / 7200 seconds)
2. Delegates to `Recordings.download_footage/6` which uses `VideoAssembler.assemble/6`
3. The `VideoAssembler` uses `Concatenater` to read samples from multiple recording files and writes them into a single output MP4 via `ExMP4.Writer`
4. The resulting file is served as a download (`Content-Disposition: attachment`) with a timestamped filename
5. The temporary file is cleaned up when the HTTP response process terminates

## Architecture

### HLS playback pipeline (`ExNVR.Pipelines.HlsPlayback`)

```
Recording source → Realtimer → [Transcoder] → Output.HLS → filesystem → HTTP
```

- **Recording source** (`ExNVR.Elements.Recording`) — A Membrane `Source` that wraps the `Concatenater` and produces H.264/H.265 buffers. Supports bounded playback via `end_date` and/or `duration` options. When both are specified, playback stops at whichever is reached first.

- **Realtimer** (`ExNVR.Elements.Realtimer`) — Paces output to real-time speed so the HLS player receives segments at the rate they should be consumed, preventing the pipeline from racing ahead.

- **Transcoder** (`ExNVR.Elements.Transcoder`) — Optional. When a `resolution` parameter is specified (240, 480, 640, 720, or 1080), decodes the video and re-encodes to H.264 Baseline at the target height. Preserves aspect ratio (width computed proportionally, rounded to multiple of 4).

- **Output.HLS** — Same HLS sink used by [live streaming](live-streaming.md), writing segments and playlists to a temporary directory.

The pipeline uses `setup: :incomplete` / `setup: :complete` to delay starting until `start_streaming/1` is called, giving the controller time to register with the `HlsStreamingMonitor` before segments start appearing.

### Concatenater (`ExNVR.Recordings.Concatenater`)

Provides a unified view over multiple MP4 recording files as a single continuous stream:

- Opens files sequentially, transparently transitioning between segments
- Handles seeking within the first recording when the start date falls mid-segment
- Normalizes timestamps across files using a fixed video timescale of 90,000
- Converts MP4 samples to Annex B format via `BitStreamFilter.MP4ToAnnexb` (configurable)
- Detects codec changes between consecutive recordings and signals `:codec_changed`
- Used by both the `Recording` element (for HLS playback) and the `VideoAssembler` (for footage downloads)

### Frontend components

**`Viewer.vue`** — The main playback interface:
- Device and stream selector dropdowns
- HLS video player (`EVideoPlayer` with HLS.js) with auto-play, muted, zoomable
- Live/recorded toggle button (pulsating red dot for live, "Go Live" link for recorded)
- Snapshot download button (captures current video frame to canvas, exports as JPEG)
- Footage download button (opens download modal)
- Stream statistics overlay (resolution, bitrate, bandwidth, codec, dropped/corrupted frames)
- Fullscreen toggle
- HLS.js config: `liveSyncDurationCount: 3`, `liveMaxLatencyDurationCount: 6`, `manifestLoadingTimeOut: 60000`

**`Timeline.vue`** — Recording availability timeline:
- Renders [runs](../domain/run.md) as green bars on a zoomable/pannable timeline (`ETimeline` component)
- Click on a run emits `run-clicked` with the timestamp, triggering playback from that point
- Auto-scales min/max dates to ±1 year from the data range
- Uses `moment-timezone` for UTC date formatting

## Data contracts

### HLS playback API

```
GET /api/devices/:device_id/hls/index.m3u8
  ?pos=2024-04-01T12:00:00Z    # Start timestamp (omit for live)
  &stream=high|low|auto         # Stream quality (default: high)
  &resolution=480               # Optional transcoding (240|480|640|720|1080)
  &duration=300                 # Optional max duration in seconds (min 5)
```

Returns `application/vnd.apple.mpegurl` master manifest with `stream_id` and `live` query params injected into variant URIs.

### Snapshot API

```
GET /api/devices/:device_id/snapshot
  ?time=2024-04-01T12:00:00Z   # Timestamp (omit for live snapshot)
  &method=before|precise        # Extraction method (default: before)
  &format=jpeg                  # Image format (currently only jpeg)
  &stream=high|low              # Stream quality (default: high)
```

Response: `image/jpeg` with `x-timestamp` header (Unix milliseconds).

### Footage download API

```
GET /api/devices/:device_id/footage
  ?start_date=2024-04-01T12:00:00Z    # Required
  &end_date=2024-04-01T12:05:00Z      # Either end_date or duration required
  &duration=300                         # Seconds (5–7200)
  &stream=high|low                     # Stream quality (default: high)
```

Response: `video/mp4` download with `x-start-date` header and timestamped filename.

### BIF thumbnails API

```
GET /api/devices/:device_id/bif/:hour
  ?hour=2024-04-01T12:00:00Z
```

Returns the [BIF file](bif-thumbnails.md) for video scrubbing previews. Cached with `immutable, max-age=1year`.

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `stream` | API param | `:high` | `:high`, `:low`, or `:auto` (auto picks low if available) |
| `resolution` | API param | `nil` | Optional transcoding: 240, 480, 640, 720, 1080 |
| `duration` | API param | `0` | Max playback/download duration in seconds (max 7200 for downloads) |
| `method` | Snapshot param | `:before` | `:before` (keyframe) or `:precise` (exact frame) |
| `:download_dir` | App config | `System.tmp_dir!/ex_nvr_downloads` | Temporary directory for footage assembly |
| HLS stale timeout | `HlsStreamingMonitor` | 45s | Idle time before shutting down playback pipeline |
