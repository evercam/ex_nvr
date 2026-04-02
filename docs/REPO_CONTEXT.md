---
repo: ex_nvr
stack: elixir-phoenix
generated_at: 2026-04-01T15:00:00Z
---

# Repo Context: ex_nvr

## What this repo does

ExNVR is a Network Video Recorder built in Elixir using the Membrane Framework. It records video streams from IP cameras and RTSP sources, stores them as MP4 segments on the local file system, and provides HLS/WebRTC playback, event handling (including LPR), event-driven triggers, and remote storage syncing. It also ships as Nerves firmware for Raspberry Pi devices used by Evercam.

## Stack

| Property | Value |
|----------|-------|
| Language | Elixir 1.19.5 / Erlang 28.1.1 |
| Framework | Phoenix 1.8 + LiveView 1.0 + Membrane Framework |
| Build tool | Mix |
| Test framework | ExUnit + Mimic |
| Frontend | Tailwind CSS + Vue (via live_vue) + Vite |
| Key dependencies | Ecto/SQLite3, ex_webrtc, ex_mp4, hlx, ex_onvif, slipstream, ex_aws_s3, Nerves, Flop, PromEx |

## Apps / Packages

Poncho-style project (each app has its own `mix.exs` at the top level, not an umbrella).

| App/Package | Path | Role |
|-------------|------|------|
| ex_nvr (ui) | `ui/` | Core NVR app: Phoenix web UI, REST API, Membrane pipelines, business logic, SQLite database |
| video_processor | `video_processor/` | C NIF for video encoding, decoding, and conversion (FFmpeg-based) |
| nerves_fw | `nerves_fw/` | Evercam Nerves firmware for RPi4/RPi5/Giraffe (OTA via NervesHub) |
| nerves_community | `nerves_community/` | Community Nerves firmware images for RPi4/RPi5 |

## Discovery Paths

| Category | Glob patterns | Description |
|----------|--------------|-------------|
| Schemas | `ui/lib/ex_nvr/model/**/*.ex`, `ui/lib/ex_nvr/events/*.ex`, `ui/lib/ex_nvr/triggers/trigger_config.ex`, `ui/lib/ex_nvr/remote_storages/remote_storage.ex` | Ecto schemas |
| Contexts | `ui/lib/ex_nvr/devices.ex`, `ui/lib/ex_nvr/recordings.ex`, `ui/lib/ex_nvr/events.ex`, `ui/lib/ex_nvr/accounts.ex`, `ui/lib/ex_nvr/triggers.ex`, `ui/lib/ex_nvr/remote_storages.ex` | Business logic modules |
| Controllers | `ui/lib/ex_nvr_web/controllers/**/*.ex` | REST API and page controllers |
| Router | `ui/lib/ex_nvr_web/router.ex` | Route definitions |
| LiveView | `ui/lib/ex_nvr_web/live/**/*.ex` | LiveView pages and components |
| Channels | `ui/lib/ex_nvr_web/channels/**/*.ex` | WebSocket channels |
| Pipelines | `ui/lib/ex_nvr/pipeline/**/*.ex`, `ui/lib/ex_nvr/pipelines/**/*.ex` | Membrane media pipelines |
| Pipeline elements | `ui/lib/ex_nvr/elements/**/*.ex` | Custom Membrane elements |
| HLS | `ui/lib/ex_nvr/hls/**/*.ex` | HLS stream processing |
| Devices | `ui/lib/ex_nvr/devices/**/*.ex` | Camera communication, ONVIF, vendor HTTP clients |
| Remote storages | `ui/lib/ex_nvr/remote_storages/**/*.ex` | S3 and HTTP storage backends |
| Triggers | `ui/lib/ex_nvr/triggers/**/*.ex` | Event-driven trigger system |
| Hardware | `ui/lib/ex_nvr/hardware/**/*.ex` | Serial port, Victron energy monitoring |
| BIF | `ui/lib/ex_nvr/bif/**/*.ex` | BIF (Base Index Frame) thumbnail generation |
| Video processor | `video_processor/lib/**/*.ex`, `video_processor/c_src/**/*` | NIF video encoding/decoding/conversion |
| Nerves FW | `nerves_fw/lib/**/*.ex` | Nerves firmware (disk mount, GPIO, Grafana, UPS, Netbird, RUT) |
| Vue components | `ui/assets/vue/**/*.vue` | Frontend Vue components (Viewer, Timeline, Schedule) |
| Config | `ui/config/*.exs` | Application configuration |
| Migrations | `ui/priv/repo/migrations/*.exs` | Database migrations |
| Metrics | `ui/lib/ex_nvr_web/prom_ex/**/*.ex` | Prometheus metrics |

## Concept Doc Template

1. **Overview** — A human-friendly explanation of what this entity is, why it exists, and how it fits into the bigger picture. Write for a new team member who needs to understand the domain, not just the code. Include the business context: who uses it, what problem it solves, what would break if it didn't exist. This section should capture institutional knowledge that isn't obvious from reading the code.
2. **Data model** — Schemas/types, key fields, associations, embedded schemas.
3. **API surface** — REST routes, methods, request/response shapes.
4. **Business logic** — Context functions, workflows, PubSub events.
5. **System integration** — OTP supervision trees, Membrane pipelines, hardware interfaces.
6. **Storage** — SQLite queries, file system layout, remote storage.
7. **Related concepts**
8. **Business rules**

## Feature Doc Template

1. **Overview** — A human-friendly explanation of what this feature does, why it exists, and how it fits into the bigger picture. Write for a new team member who needs to understand the domain, not just the code. Include the business context: who uses it, what problem it solves, what would break if it didn't exist.
2. **How it works** — System-level flow (route -> controller -> context -> pipeline -> storage -> response).
3. **Architecture** — Relevant files, supervision tree, Membrane pipeline topology.
4. **Integrations** — Hardware, network protocols (RTSP, ONVIF, WebRTC), external services.
5. **Data contracts** — JSON shapes, WebSocket messages, HLS playlist formats.
6. **Configuration** — Environment variables, runtime config.

## Suggested Concepts

| Concept | Key files | Notes |
|---------|-----------|-------|
| device | `ui/lib/ex_nvr/model/device.ex`, `ui/lib/ex_nvr/devices.ex`, `ui/lib/ex_nvr/devices/**/*.ex` | Central entity — IP camera or RTSP source with credentials, stream config, state machine |
| recording | `ui/lib/ex_nvr/model/recording.ex`, `ui/lib/ex_nvr/recordings.ex` | Stored video segment with start/end timestamps, links to runs |
| run | `ui/lib/ex_nvr/model/run.ex` | A recording session (e.g. one RTSP session from start to finish) |
| user | `ui/lib/ex_nvr/accounts/user.ex`, `ui/lib/ex_nvr/accounts.ex` | Authentication and authorization (bcrypt, tokens, roles) |
| event | `ui/lib/ex_nvr/events/event.ex`, `ui/lib/ex_nvr/events.ex` | Generic device events (webhook-ingested) |
| lpr-event | `ui/lib/ex_nvr/events/lpr.ex` | License Plate Recognition events with plate metadata and images |
| remote-storage | `ui/lib/ex_nvr/remote_storages/remote_storage.ex`, `ui/lib/ex_nvr/remote_storages.ex` | S3 or HTTP storage backends for uploading recordings/snapshots |
| trigger-config | `ui/lib/ex_nvr/triggers/trigger_config.ex`, `ui/lib/ex_nvr/triggers.ex` | Event-to-action trigger rules (source -> target) |
| schedule | `ui/lib/ex_nvr/model/schedule.ex` | Recording/device schedules (weekly time slots) |

## Suggested Features

| Feature | Key files | Notes |
|---------|-----------|-------|
| video-recording | `ui/lib/ex_nvr/pipelines/main.ex`, `ui/lib/ex_nvr/pipeline/output/storage.ex`, `ui/lib/ex_nvr/elements/recording.ex` | Core recording pipeline: RTSP -> Membrane -> MP4 segments on disk |
| live-streaming | `ui/lib/ex_nvr/pipeline/output/hls.ex`, `ui/lib/ex_nvr/pipeline/output/web_rtc.ex`, `ui/lib/ex_nvr/hls/processor.ex` | HLS and WebRTC live view from cameras |
| playback | `ui/lib/ex_nvr/pipelines/hls_playback.ex`, `ui/assets/vue/Viewer.vue`, `ui/assets/vue/Timeline.vue` | Recorded footage playback with timeline scrubbing |
| event-ingestion | `ui/lib/ex_nvr_web/controllers/api/event_controller.ex`, `ui/lib/ex_nvr/events.ex` | Webhook API for generic and LPR event ingestion |
| triggers | `ui/lib/ex_nvr/triggers/**/*.ex`, `ui/lib/ex_nvr_web/live/trigger_config_live.ex` | Event-driven automation: source events -> target actions |
| device-management | `ui/lib/ex_nvr_web/live/device_live.ex`, `ui/lib/ex_nvr_web/controllers/api/device_controller.ex` | CRUD, state management, ONVIF auto-config for cameras |
| onvif-discovery | `ui/lib/ex_nvr/devices/onvif/**/*.ex`, `ui/lib/ex_nvr_web/live/onvif_discovery_live.ex` | Discover IP cameras on the network via ONVIF |
| snapshot-upload | `ui/lib/ex_nvr/devices/snapshot_uploader.ex`, `ui/lib/ex_nvr/pipeline/output/socket.ex` | Periodic snapshots sent via unix socket or uploaded to remote storage |
| remote-storage-sync | `ui/lib/ex_nvr/remote_storages/**/*.ex` | Upload recordings/snapshots to S3 or HTTP endpoints |
| bif-thumbnails | `ui/lib/ex_nvr/bif/**/*.ex` | Generate BIF (Base Index Frame) thumbnails for video scrubbing |
| user-auth | `ui/lib/ex_nvr/accounts.ex`, `ui/lib/ex_nvr_web/live/user_login_live.ex` | User registration, login, password reset, role-based access |
| system-monitoring | `ui/lib/ex_nvr/disk_monitor.ex`, `ui/lib/ex_nvr/system_status.ex`, `ui/lib/ex_nvr_web/prom_ex/**/*.ex` | Disk usage monitoring, system status reporting, Prometheus metrics |
| nerves-firmware | `nerves_fw/lib/**/*.ex` | Embedded device firmware: GPIO, disk mounting, UPS monitoring, Netbird VPN, remote configuration |
