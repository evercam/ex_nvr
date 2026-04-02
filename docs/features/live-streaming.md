---
name: live-streaming
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/pipeline/output/hls.ex
  - ui/lib/ex_nvr/pipeline/output/web_rtc.ex
  - ui/lib/ex_nvr/hls/processor.ex
  - ui/lib/ex_nvr/pipelines/main.ex
  - ui/lib/ex_nvr_web/controllers/api/device_streaming_controller.ex
  - ui/lib/ex_nvr_web/hls_streaming_monitor.ex
  - ui/lib/ex_nvr_web/channels/device_room_channel.ex
  - ui/lib/ex_nvr/elements/video_stream_stat_reporter.ex
  - ui/lib/ex_nvr/elements/transcoder.ex
  - ui/lib/ex_nvr/elements/cvs_bufferer.ex
relates_to:
  concepts: [device]
  features: [video-recording, playback]
---

## Overview

**Live streaming** delivers real-time camera video to browser clients through two protocols: **HLS** (HTTP Live Streaming) for broad compatibility and **WebRTC** for low-latency viewing. Both protocols are fed from the same Membrane pipeline that also handles [video recording](video-recording.md) — the main pipeline's `Tee` elements fan out each stream to HLS and WebRTC sinks alongside the storage sink.

Live streaming operates independently of recording. A [device](../domain/device.md) in `:streaming` state (connected but not recording) still serves live video to HLS and WebRTC clients. This means operators can monitor cameras in real-time even when recording is disabled by schedule, manual stop, or `recording_mode: :never`.

The feature also includes **live snapshots** — on-demand JPEG frames decoded from the live stream without decoding every frame. The `CVSBufferer` element keeps only the last Coded Video Sequence (keyframe + dependent frames) in memory and decodes it on request.

Additionally, **stream statistics** (bitrate, FPS, resolution, GOP size) are computed by the `VideoStreamStatReporter` element and broadcast via PubSub for the device details UI.

## How it works

### HLS live streaming

1. Client requests `GET /api/devices/:id/hls/index.m3u8` (no `pos` parameter = live mode)
2. `DeviceStreamingController.hls_stream/2` resolves the HLS directory (`{hls_dir}/{device_id}/{stream}/live/`) where the pipeline is already writing segments
3. The controller registers the stream with `HlsStreamingMonitor`, reads the master manifest, injects `stream_id` and `live` query params into all URIs, and returns it
4. The client fetches media playlist and segment files via `GET /api/devices/:id/hls/*path?stream_id=...&live=true`
5. Each media playlist request updates the `HlsStreamingMonitor` last access time
6. After 45 seconds of no requests, `HlsStreamingMonitor` cleans up the registration

The HLS output (`Output.HLS`) creates playlists using the `HLX.Writer` library with a rolling window of 6 segments. It handles:
- Codec detection (H.264 or H.265) from the first stream format
- Discontinuity markers on stream format changes or connection loss
- Cleanup of the HLS directory on element shutdown via Membrane's `ResourceGuard`

### WebRTC live streaming

1. Client opens a Phoenix channel on `"device:{device_id}"` with optional `stream` parameter (`"high"` or `"low"`)
2. `DeviceRoomChannel.join/3` calls `MainPipeline.add_webrtc_peer/2`, which notifies the `Output.WebRTC` element
3. The WebRTC element creates a `PeerConnection` with configured ICE servers, adds a video track, generates an SDP offer, and sends it to the channel process
4. The channel pushes the `"offer"` event to the client
5. The client sends back an `"answer"` and `"ice_candidate"` messages, forwarded via the pipeline to the WebRTC element
6. Once the peer connection reaches `:connected` state, RTP packets are sent to the peer
7. When the channel process terminates (client disconnects), the peer connection is closed and cleaned up

The WebRTC element (`Output.WebRTC`) supports:
- Multiple concurrent peers per stream (maintains a `peers` map)
- H.264 and H.265 codecs with 90,000 clock rate
- RTP packetization via `RTSP.RTP.Encoder.H264` / `Encoder.H265`
- Automatic peer cleanup on connection failure or process death (via `Process.monitor`)
- Packets are only sent to peers in `:connected` state

### Live snapshots

1. `GET /api/devices/:id/snapshot` (no `time` parameter) triggers a live snapshot
2. First attempts `Devices.fetch_snapshot/1` (HTTP snapshot from camera's `snapshot_uri`)
3. If that fails and the device is recording, falls back to `Main.live_snapshot/2`
4. The pipeline notifies the `CVSBufferer` (`:snapshooter`) element with `:snapshot`
5. `CVSBufferer` decodes the buffered keyframe + subsequent frames, encodes the last frame as JPEG, and notifies the parent
6. The pipeline replies to all waiting callers (supports concurrent requests by collecting PIDs)
7. Response includes an `x-timestamp` header with the snapshot's Unix timestamp

## Architecture

### Pipeline output topology

```
main_stream Tee ──┬── Output.HLS (main)       → /hls/{device_id}/high/live/
                  ├── Output.WebRTC (main)     → PeerConnections (high quality)
                  ├── CVSBufferer              → Live snapshot on demand
                  └── VideoStreamStatReporter  → PubSub stats

sub_stream Tee ───┬── Output.HLS (sub)         → /hls/{device_id}/low/live/
                  ├── Output.WebRTC (sub)       → PeerConnections (low quality)
                  └── VideoStreamStatReporter   → PubSub stats
```

Both main and sub streams get independent HLS and WebRTC outputs. The HLS and WebRTC sinks are always present when the stream is connected — they don't depend on recording being active.

### HLS streaming monitor (`ExNVRWeb.HlsStreamingMonitor`)

A GenServer using an ETS table to track active HLS sessions. Each session entry stores:
- `id` — unique stream ID (generated token)
- `path` — filesystem path to the HLS directory
- `cleanup_fn` — function to call on cleanup (for playback: stops the pipeline; for live: no-op)
- `last_access_time` — Unix timestamp of last manifest request

Polls every 3 seconds, cleaning up sessions idle for 45+ seconds. For live streams, cleanup just removes the ETS entry. For playback streams, it also stops the `HlsPlayback` pipeline.

### Stream statistics (`VideoStreamStatReporter`)

A Membrane `Sink` that computes real-time stream metrics:
- Average bitrate (bits/sec, calculated from total bytes and elapsed monotonic time)
- Average FPS (frames / elapsed time)
- Average GOP size (running average of inter-keyframe distances)
- Resolution and codec profile (from stream format)

Reports every 10 seconds via:
1. `notify_parent: {:stats, stats}` — pipeline stores in track state
2. PubSub broadcast on `"stats:{device_id}"` with `{:video_stats, {stream, stats}}`

Telemetry events:
- `[:ex_nvr, :device, :stream, :info]` — emitted on stream format change (codec, resolution, profile)
- `[:ex_nvr, :device, :stream, :frame]` — emitted per frame (size, GOP size)

### Transcoder (`ExNVR.Elements.Transcoder`)

A Membrane `Filter` for resolution downscaling. Decodes H.264/H.265 input, re-encodes to H.264 Baseline at a target height (preserving aspect ratio). Used by the [playback](playback.md) pipeline when a `resolution` parameter is specified, not by live streaming directly.

## Integrations

### WebRTC / ICE

ICE servers are configured via the `:ice_servers` application config (JSON string). Falls back to `stun:stun.l.google.com:19302` if unconfigured or invalid. Supports both STUN and TURN servers.

### Phoenix Channels

WebRTC signaling uses Phoenix Channels (`ExNVRWeb.DeviceRoomChannel`). The channel joins topic `"device:{device_id}"` and handles three message types:
- Outgoing: `"offer"` (SDP offer JSON), `"ice_candidate"` (ICE candidate JSON)
- Incoming: `"answer"` (SDP answer JSON), `"ice_candidate"` (ICE candidate JSON)

### HLS libraries

- `HLX` — HLS playlist writer (master + media playlists, segment management)
- `ExM3U8` — M3U8 parser/serializer used by `HLS.Processor` for manifest manipulation

## Data contracts

### HLS manifest manipulation (`HLS.Processor`)

The processor transforms generated manifests before serving them to clients:

- **`delete_stream/2`** — Removes variant streams from a master playlist by URI prefix
- **`add_query_params/3`** — Injects query parameters (`stream_id`, `live`) into all URIs in both master and media playlists, enabling the streaming monitor to track sessions

### WebRTC signaling messages

| Direction | Channel event | Payload |
|-----------|--------------|---------|
| Server → Client | `"offer"` | `%{data: <JSON SDP offer>}` |
| Server → Client | `"ice_candidate"` | `%{data: <JSON ICE candidate>}` |
| Client → Server | `"answer"` | JSON SDP answer string |
| Client → Server | `"ice_candidate"` | JSON ICE candidate string |

### Snapshot response

```
HTTP/1.1 200 OK
Content-Type: image/jpeg
x-timestamp: <unix_milliseconds>

<JPEG binary>
```

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `:ice_servers` | App config | Google STUN | JSON list of ICE/TURN servers |
| HLS max segments | `Output.HLS` | 6 | Rolling window size for live playlists |
| Stale timeout | `HlsStreamingMonitor` | 45s | Idle time before cleaning up an HLS session |
| Stats interval | `VideoStreamStatReporter` | 10s | How often stats are reported |
| Snapshot format | API parameter | `:jpeg` | Currently only JPEG is supported |
