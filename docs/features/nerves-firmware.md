---
name: nerves-firmware
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - nerves_fw/lib/nerves_fw/application.ex
  - nerves_fw/lib/nerves_fw/disk_mounter.ex
  - nerves_fw/lib/nerves_fw/gpio.ex
  - nerves_fw/lib/nerves_fw/grafana_agent.ex
  - nerves_fw/lib/nerves_fw/grafana_agent/config_renderer.ex
  - nerves_fw/lib/nerves_fw/netbird.ex
  - nerves_fw/lib/nerves_fw/netbird/client.ex
  - nerves_fw/lib/nerves_fw/monitoring/ups.ex
  - nerves_fw/lib/nerves_fw/monitoring/power_schedule.ex
  - nerves_fw/lib/nerves_fw/remote_configurer.ex
  - nerves_fw/lib/nerves_fw/remote_configurer/router.ex
  - nerves_fw/lib/nerves_fw/remote_configurer/step.ex
  - nerves_fw/lib/nerves_fw/remote_config_handler.ex
  - nerves_fw/lib/nerves_fw/rut.ex
  - nerves_fw/lib/nerves_fw/rut/auth.ex
  - nerves_fw/lib/nerves_fw/rut/scheduler.ex
  - nerves_fw/lib/nerves_fw/system_status.ex
  - nerves_fw/lib/nerves_fw/system_settings.ex
  - nerves_fw/lib/nerves_fw/health/metadata.ex
relates_to:
  concepts: [device, schedule]
  features: [system-monitoring]
---

## Overview

**Nerves firmware** is the embedded device layer that runs ExNVR on Raspberry Pi hardware as a self-contained Linux appliance. It handles everything that a traditional NVR server takes for granted but an embedded device must manage explicitly: disk mounting, VPN connectivity, power management (UPS monitoring via GPIO and scheduled power cycling), remote provisioning, observability (log and metric shipping to Grafana Cloud), and router integration.

The firmware is built with [Nerves](https://nerves-project.org/) and ships as complete images for three hardware targets:
- **RPi4** and **RPi5** — Via `nerves_fw/` (Evercam branded) and `nerves_community/` (community images)
- **Giraffe** — A custom Evercam hardware platform with target-specific initialization

This is the code that turns a Raspberry Pi + SSD + camera into a field-deployable, remotely-managed NVR unit. Without it, ExNVR would only run as a traditional server application.

## How it works

### Boot and provisioning

1. The firmware boots with Nerves, starts the `ExNVR.Nerves.Application` supervisor
2. `SystemSettings` loads persisted configuration from `/data/settings.json`
3. If the device is not yet configured (`configured: false` or no `kit_serial`):
   - `RemoteConfigurer` contacts the Evercam cloud via WebSocket (`RemoteConnection`)
   - Sends device identifiers (MAC address, serial number, platform, gateway MAC)
   - Receives configuration: VPN setup key, admin credentials, Grafana endpoints, gateway/router config
   - Executes five configuration steps in parallel:
     - **Netbird VPN** — Connects to `vpn.evercam.io` with the provisioned setup key
     - **Disk formatting** — Finds unformatted drives, creates GPT partition + ext4 filesystem, adds to fstab
     - **User creation** — Creates an admin user with provisioned credentials
     - **Grafana Agent** — Configures log/metric shipping (Prometheus → Grafana Cloud)
     - **Router config** — Configures the network gateway (RUT router integration)
   - Reports completion back to the cloud and marks the device as configured

### Disk management (`DiskMounter`)

Manages external storage (SSD/HDD) mounting via a persistent fstab at `/data/fstab`:

- On boot, mounts all filesystems declared in fstab via `mount -T /data/fstab -a`
- Subscribes to `NervesUEvent` for hot-plug events — auto-mounts when a new block device is connected
- Creates a generic "disk" event when a block device is disconnected
- Provides `add_fstab_entry/3`, `delete_fstab_entries/1`, `mount/0`, `umount/1` API
- Lazy unmount support (`umount -l`) for safe disconnect during recording

### UPS monitoring (`Monitoring.UPS`)

Monitors AC power and battery state via GPIO pins on RPi (not available on Giraffe):

- Reads two GPIO pins: AC power (default GPIO27) and low battery (default GPIO22) via `Circuits.GPIO`
- Uses 1-second debounce to filter signal noise
- On pin state change, creates a generic event (`"power"` or `"low-battery"`)
- Waits `trigger_after` seconds (default 30) before taking action (to avoid transient fluctuations)
- Configurable actions for AC failure and low battery: `:power_off`, `:stop_recording`, or `:nothing`
- **AC failure + power_off**: Stops all recordings, unmounts disks, calls `Nerves.Runtime.poweroff/0`
- **AC failure + stop_recording**: Stops recording on all devices, unmounts disks. Resumes recording when power returns.
- Auto-enables UPS monitoring if GPIO pins detect a signal on startup (even if `enabled: false`)

### Power schedule (`Monitoring.PowerSchedule`)

Uses the same [schedule](../domain/schedule.md) system as recording schedules, but for device power:

- Reads schedule from `SystemSettings.power_schedule`
- Checks every 15 seconds if the current time (in configured timezone) is within the schedule
- If outside the schedule, triggers the configured action (`:power_off` or `:stop_recording`)
- Waits for NTP sync before enforcing the schedule (skips check if time isn't synchronized)
- Creates a `"shutdown"` event before powering off

### VPN connectivity (`Netbird`)

Manages a [Netbird](https://netbird.io/) VPN daemon for remote access:

- Runs `netbird service run` as a MuonTrap daemon with configuration at `/data/netbird/`
- Provides `up/3` (connect with management URL + setup key), `down/0`, `status/0` API
- Disables the Netbird firewall in the config file
- Logs Netbird output with mapped log levels (ERRO → error, WARN → warning)

### Observability (`GrafanaAgent`)

Ships logs and Prometheus metrics to Grafana Cloud:

- Downloads Grafana Agent binary from GitHub releases on first boot
- Generates config YAML from a template with Prometheus remote_write and Loki endpoints
- Runs as a MuonTrap daemon
- Identifies the device by kit ID, serial number, and MAC address

### System settings

Persisted as JSON at `/data/settings.json`, managed by `SystemSettings` GenServer:

- **`kit_serial`** — Device identifier assigned during provisioning
- **`configured`** — Whether initial provisioning is complete
- **`power_schedule`** — Schedule map, timezone, action (power_off/stop_recording/nothing)
- **`router`** — Gateway router credentials (for RUT integration)
- **`ups`** — UPS monitoring config: enabled flag, GPIO pins, actions, trigger delay

Changes broadcast `{:system_settings, :update}` on `ExNVR.Nerves.PubSub` so UPS and power schedule monitors can react immediately.

## Architecture

### Supervision tree

```
ExNVR.Nerves.Supervisor (one_for_one)
├── Phoenix.PubSub (ExNVR.Nerves.PubSub)
├── SystemSettings
├── Netbird (Supervisor)
│   ├── MuonTrap.Daemon (netbird service)
│   └── Netbird.Client
├── DiskMounter
├── GrafanaAgent
├── MuonTrap.Daemon (nginx)
├── RemoteConfigurer (transient)
├── PowerSchedule (transient)
├── RUT.Auth
├── SystemStatus
├── Monitoring.UPS (RPi only, not Giraffe)
└── Giraffe.Init (Giraffe target only)
```

### Target-specific behavior

| Component | RPi4/RPi5 | Giraffe |
|-----------|-----------|---------|
| UPS monitoring | Yes (GPIO) | No |
| Giraffe.Init | No | Yes |
| Common services | Yes | Yes |

### RUT integration

`ExNVR.Nerves.RUT` modules integrate with Teltonika RUT routers (common in field deployments):
- `RUT.Auth` — Authenticates with the router's HTTP API
- `RUT.Scheduler` — Schedules router operations
- `RUT.SystemInformation` — Queries router system info
- `Router` (RemoteConfigurer) — Applies gateway configuration during provisioning

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `enabled` | `ups` settings | `false` | UPS monitoring master switch |
| `ac_pin` | `ups` settings | `GPIO27` | AC power detection GPIO pin |
| `battery_pin` | `ups` settings | `GPIO22` | Low battery detection GPIO pin |
| `ac_failure_action` | `ups` settings | `:stop_recording` | Action on AC power loss |
| `low_battery_action` | `ups` settings | `:nothing` | Action on low battery |
| `trigger_after` | `ups` settings | `30` | Seconds to wait before acting |
| `schedule` | `power_schedule` | `nil` | Weekly power schedule (nil = always on) |
| `timezone` | `power_schedule` | `"UTC"` | Timezone for schedule evaluation |
| `action` | `power_schedule` | `:power_off` | Action when outside schedule |
| `fstab` | `DiskMounter` | `/data/fstab` | Persistent fstab file location |
| Target | App config | — | `:host`, `:rpi4`, `:rpi5`, `:giraffe` |
