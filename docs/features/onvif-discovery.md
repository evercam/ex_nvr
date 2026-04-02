---
name: onvif-discovery
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/devices/onvif.ex
  - ui/lib/ex_nvr/devices/onvif/**/*.ex
  - ui/lib/ex_nvr_web/controllers/api/onvif_controller.ex
  - ui/lib/ex_nvr_web/live/onvif_discovery_live.ex
  - ui/lib/ex_nvr_web/live/onvif/**/*.ex
  - ui/lib/ex_nvr/devices/cameras/device_info.ex
  - ui/lib/ex_nvr/devices/cameras/stream_profile.ex
  - ui/lib/ex_nvr/devices/cameras/network_interface.ex
  - ui/lib/ex_nvr/devices/cameras/ntp.ex
relates_to:
  concepts: [device]
  features: [device-management]
---

## Overview

**ONVIF discovery** allows admins to find IP cameras on the local network, inspect their configuration, auto-configure optimal stream profiles, and add them to ExNVR — all from a single page. Without this feature, operators would need to manually determine each camera's IP address, RTSP URI, and stream parameters before creating a device.

ONVIF (Open Network Video Interface Forum) is an industry standard protocol that most IP cameras support. ExNVR uses the `ex_onvif` library to perform WS-Discovery probes on the network, authenticate with cameras, read their configuration (stream profiles, network interfaces, NTP settings, on-camera recordings), and configure video encoder settings.

The feature provides:
1. **Network scanning** — Broadcast probe on a selected network interface to find ONVIF-compatible cameras
2. **Camera authentication** — Connect to a discovered camera with username/password to access its ONVIF services
3. **Configuration inspection** — View hardware info, network config, date/time settings, and stream profiles in a tabbed detail panel
4. **Auto-configuration** — One-click optimal stream setup (vendor-aware: AXIS cameras get dedicated `ex_nvr_main`/`ex_nvr_sub` profiles; other vendors configure the first two existing profiles)
5. **Add to NVR** — Pre-populate the [device creation](device-management.md) form with discovered camera details

## How it works

### Discovery flow

1. Admin opens `/onvif/discover` and selects a network interface IP and probe timeout
2. Clicks "Scan Network" → `ExNVR.Devices.Onvif.discover/1` sends a WS-Discovery probe via `ExOnvif.Discovery.probe/1`
3. Results are deduplicated and link-local addresses (`169.254.*`) are filtered out
4. Each discovered probe result appears as a card showing camera name (from ONVIF scopes) and IP

### Authentication flow

1. Admin clicks "Authenticate" on a discovered camera → modal with username/password
2. `ExOnvif.Device.init/3` connects to the camera's ONVIF services
3. On success, the camera's full configuration is loaded:
   - Network interfaces via `ExOnvif.Devices.get_network_interfaces/1`
   - NTP settings via `ExOnvif.Devices.get_ntp/1` (only if `date_time_type` is `:ntp`)
   - Stream profiles via `ExOnvif.Media2.get_profiles/1`, sorted to prioritize `ex_nvr_main` and `ex_nvr_sub` profile names
   - Stream URIs and snapshot URIs for each profile

### Auto-configuration

Clicking "Auto Configure" calls `Devices.Onvif.auto_configure/1`, which applies vendor-specific stream configuration:

**AXIS cameras** — Creates dedicated profiles named `ex_nvr_main` and `ex_nvr_sub` if they don't exist. Finds unused video encoder configurations to avoid conflicting with existing profiles. Sets quality to 70.

**Other vendors** — Configures the first two existing profiles (main and sub stream).

Both paths apply the same encoding targets:

| Stream | Target codec | Bitrate | GOP multiplier | Resolution |
|--------|-------------|---------|-----------------|------------|
| Main | H.265 (fallback: H.264) | 3072 kbps | 4x framerate | Best available (prefers 3840x2160) |
| Sub | H.264 | 572 kbps | 2x framerate | First resolution ≤1000px height/width |

Frame rate is selected as the lowest available rate ≥8 FPS. The `AutoConfig` struct tracks which streams were successfully configured.

### Add to NVR flow

Clicking "Add to NVR" redirects to `/devices/new` with flash params pre-populated:
- `name`, `type` (`:ip`), `vendor`, `model`, `mac` (from network interface)
- `url` (camera's ONVIF address)
- `stream_config` with `stream_uri`, `snapshot_uri`, `profile_token` for main (and optionally sub) stream
- `credentials` with `username` and `password`

The `DeviceLive` mount reads these from flash and pre-fills the form.

## Architecture

### `ExNVR.Devices.Onvif` module

Core functions:
- `discover/1` — WS-Discovery probe with optional `ip_address` and `timeout`
- `onvif_device/1` — Creates an `ExOnvif.Device` from an ExNVR `Device` (for existing devices)
- `all_config/1` — Fetches stream profiles, camera information, local date/time, and on-camera recordings for an existing device
- `auto_configure/1` — Vendor-aware stream profile configuration
- `get_recordings/1` — Retrieves on-camera recordings via ONVIF Search service

### LiveView page (`OnvifDiscoveryLive`)

A single-page application with three sections:
1. **Discovery settings** — Network interface dropdown (from `:inet.getifaddrs/0`) and timeout input
2. **Device list** — Discovered cameras with Authenticate/View Details buttons
3. **Device details** — Four tabs (System, Network, Date & Time, Streams) with Auto Configure and Add to NVR buttons

State management uses the `CameraDetails` struct per discovered camera, tracking the probe result, ONVIF device connection, network interface, NTP config, stream profiles, and UI state.

### REST API

| Method | Path | Auth | Action |
|--------|------|------|--------|
| `GET/POST` | `/api/onvif/discover` | Admin | Discover cameras on network |

Parameters: `probe_timeout` (integer, 1–60 seconds, default 2), `ip_address` (optional), `username`, `password`. Returns discovered devices — if credentials are provided, attempts `ExOnvif.Device.init/3` to return fully initialized device info; otherwise returns raw probe results.

## Integrations

### ONVIF protocol (via `ex_onvif`)

| ONVIF service | Usage |
|---------------|-------|
| WS-Discovery | Network camera discovery (`ExOnvif.Discovery.probe/1`) |
| Device Management | Network interfaces, NTP, system date/time |
| Media2 | Stream profiles, video encoder config, stream URIs, snapshot URIs |
| Search | On-camera recordings (via `FindRecordings`/`GetRecordingSearchResults`) |

### Camera data structs

Internal structs normalize ONVIF responses for UI rendering:
- `ExNVR.Devices.Cameras.StreamProfile` — Normalized stream profile with codec, resolution, bitrate, GOP, and smart codec flag
- `ExNVR.Devices.Cameras.NetworkInterface` — IP address, MAC, DHCP status
- `ExNVR.Devices.Cameras.NTP` — NTP enabled/server
- `ExNVR.Devices.Cameras.DeviceInfo` — Vendor, model, serial, firmware

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| Probe timeout | UI / API param | 2s | How long to wait for ONVIF responses (max 60s) |
| IP address | UI / API param | — | Network interface to probe from |
| Credentials | UI input | — | Camera username/password for ONVIF authentication |
