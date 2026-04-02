---
name: system-monitoring
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/system_status.ex
  - ui/lib/ex_nvr/disk_monitor.ex
  - ui/lib/ex_nvr_web/controllers/api/system_status_controller.ex
  - ui/lib/ex_nvr_web/prom_ex/device.ex
  - ui/lib/ex_nvr_web/prom_ex/device_stream.ex
  - ui/lib/ex_nvr_web/prom_ex/recording.ex
  - ui/lib/ex_nvr_web/prom_ex/system_status.ex
  - ui/lib/ex_nvr/hardware/victron.ex
  - ui/lib/ex_nvr/hardware/serial_port_checker.ex
relates_to:
  concepts: [device]
  features: [nerves-firmware]
---

## Overview

**System monitoring** provides visibility into the health and performance of the ExNVR system — CPU, memory, disk usage, device states, stream statistics, recording metrics, and (on embedded deployments) solar charger / battery data from Victron Energy hardware.

The feature has three layers:

1. **System status API** — A GenServer (`ExNVR.SystemStatus`) that collects system metrics every 15 seconds and serves them via `GET /api/system/status`. Used by external monitoring dashboards and the Evercam cloud platform (via Slipstream WebSocket) to track NVR health.

2. **Prometheus metrics** — Four PromEx plugins that expose metrics in Prometheus format for Grafana dashboards: device state, camera stream info, per-frame stream statistics, recording segment metrics, and Victron solar charger data.

3. **Hardware monitoring** — The `ExNVR.Hardware.Victron` GenServer reads MPPT solar charger and SmartShunt battery monitor data from Victron Energy devices connected via serial port. This is essential for solar-powered embedded deployments where battery state determines whether cameras should keep recording.

## How it works

### System status collection

`ExNVR.SystemStatus` is a GenServer started in the application supervision tree. Every 15 seconds it collects:

- **CPU**: Load averages (1/5/15 min via `:cpu_sup`), number of cores
- **Memory**: System memory data via `:memsup.get_system_memory_data/0`
- **Block storage**: List of drives (MMC, SATA, USB, NVMe) via `ExNVR.Disk.list_drives/1`
- **Static info**: Application version, hostname, serial ports, device serial number and model (from `/sys/firmware/devicetree/base/` on embedded devices)

On `get_all/0` calls, it also fetches live device summary via `ExNVR.Devices.summary/0` (async-streams over all devices collecting state, stream stats, and ONVIF config).

External systems can also push data into the status store via `set/2` — the Victron hardware module uses this to store solar charger and battery monitor data.

### Prometheus metrics (PromEx plugins)

**Device state** (`PromEx.Device`) — Polls every 15s:
- `ex_nvr.device.state` — Last value per device/state combination (one-hot encoding: value 1 for current state, 0 for others)
- `ex_nvr.camera.info` — Camera hardware info (vendor, model, serial, firmware) from vendor HTTP clients
- `ex_nvr.camera.stream.info` — Stream profile details (codec, resolution, bitrate, smart codec) from vendor HTTP clients

**Device stream** (`PromEx.DeviceStream`) — Event-driven (from `VideoStreamStatReporter`):
- `ex_nvr.device.stream.info` — Stream format info (codec, profile, resolution) per device/stream
- `ex_nvr.device.stream.gop_size` — GOP size per device/stream
- `ex_nvr.device.stream.frames.total` — Frame counter per device/stream
- `ex_nvr.device.stream.receive.bytes.total` — Total bytes received per device/stream

**Recording** (`PromEx.Recording`) — Event-driven (from `Pipeline.Output.Storage`):
- `ex_nvr.recording.total` — Counter of recorded segments per device/stream
- `ex_nvr.recording.duration.milliseconds` — Distribution of segment durations (buckets: 60.5s, 65s, 70s, 75s)
- `ex_nvr.recording.size.bytes` — Distribution of segment sizes (buckets: 500KB–40MB)

**Solar charger** (`PromEx.SystemStatus`) — Polls every 15s from `SystemStatus`:
- `ex_nvr.solar_charger.info` — Charger identification (vendor, product ID, firmware, serial)
- `ex_nvr.solar_charger.voltage` — Battery voltage (mV)
- `ex_nvr.solar_charger.current` — Battery current (mA)
- `ex_nvr.solar_charger.panel_voltage` — Solar panel voltage (mV)
- `ex_nvr.solar_charger.panel_power` — Solar panel power (W)

### Victron Energy hardware

`ExNVR.Hardware.Victron` is a GenServer that communicates with Victron MPPT solar chargers and SmartShunt battery monitors via serial port (`Circuits.UART`) at 19200 baud.

**Lifecycle**:
1. `SerialPortChecker` polls for new serial ports every minute, filtering out system ports (`ttyS0`, `ttyS1`, `ttyAMA0`, `ttyAMA10`)
2. For each new port, starts a `Victron` GenServer under `ExNVR.Hardware.Supervisor` (DynamicSupervisor)
3. The Victron process opens the port and probes for Victron text protocol (key\tvalue format)
4. If not a Victron device, exits normally (`:transient` restart)
5. If valid, reads continuous text-protocol data and parses fields (voltage, current, panel power, SOC, etc.)
6. Every 15 seconds, reports data to `SystemStatus.set/2` — SmartShunt data goes to `:battery_monitor`, MPPT data goes to `:solar_charger`
7. Restarts the UART connection every hour to prevent the Victron from getting stuck

**Supported data fields**: Battery voltage/current, panel voltage/power, load current, state of charge, time to go, charge cycle counts, yield statistics, alarm state/reasons, operation state (off/bulk/absorption/float/equalize), firmware version, product ID, serial number.

**Load output control**: Supports reading and writing the MPPT load output state via hex protocol commands (`:7ABED00B6` for read, `:8ABED00{value}{checksum}` for write).

### Disk monitoring

`ExNVR.DiskMonitor` (covered in [video-recording](video-recording.md)) is part of this monitoring surface — it polls disk usage every minute via `:disksup` and triggers oldest-recording deletion when usage exceeds the device's `full_drive_threshold`.

## Architecture

### API

| Method | Path | Auth | Action |
|--------|------|------|--------|
| `GET` | `/api/system/status` | Admin only | Returns full system status JSON |

Authorization: `authorize(user, :system, :read)` — only admin users can access system status.

### Supervision tree

```
Application
├── ExNVR.SystemStatus              — System metrics collector
├── ExNVR.Hardware.Supervisor       — DynamicSupervisor for Victron processes
│   └── ExNVR.Hardware.Victron      — One per serial port
├── ExNVR.Hardware.SerialPortChecker — Periodic serial port scanner
└── ExNVRWeb.PromEx                 — Prometheus metrics (PromEx plugins)
```

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| Metrics poll rate | PromEx plugins | 15s | How often polling metrics are collected |
| System metrics interval | `SystemStatus` | 15s | CPU/memory/disk collection frequency |
| Serial port check interval | `SerialPortChecker` | 1 min | How often to scan for new serial ports |
| Victron reporting interval | `Victron` | 15s | How often Victron data is pushed to SystemStatus |
| Victron restart interval | `Victron` | 1 hour | Periodic UART reconnection to prevent stalls |
| Ignored serial ports | `SerialPortChecker` | `ttyS0`, `ttyS1`, `ttyAMA0`, `ttyAMA10` | System ports to skip |
