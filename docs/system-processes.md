# System Processes Overview

This document explains how ExNVR starts on embedded targets and details the main background services that keep the system running.  It also outlines tasks started by the web application for each camera.

## Boot Sequence

1. **Erlinit and Shoehorn** – On embedded targets the bootloader runs `erlinit` which starts the BEAM VM.  `shoehorn` ensures `:nerves_runtime` and `:nerves_pack` are started before the main application.  See `config/target.exs`.
2. **Application start** – `ExNVR.Nerves.Application.start/2` runs, applies database migrations and builds the supervision tree based on the hardware target.
3. **Target specific children** – The `giraffe` target powers up the HDD and PoE via `ExNVR.Nerves.Giraffe.Init`.  Other targets launch the power monitoring process instead.

For a detailed walkthrough see [boot-sequence.md](boot-sequence.md).

## Firmware Services

The Nerves supervisor starts several processes common to all targets:

### Netbird
Provides VPN connectivity.  `ExNVR.Nerves.Netbird` launches a `netbird` daemon and a control client for issuing commands.

### DiskMounter
Listens for udev events and mounts any drives listed in `/data/fstab`.  It can add or remove entries programmatically.

### GrafanaAgent
Ensures a Grafana Agent binary and configuration exist.  If missing, the binary is downloaded from GitHub.  It then starts the agent via `MuonTrap.Daemon`.

### nginx
The web interface is served through an `nginx` daemon started under `MuonTrap`.

### RemoteConfigurer
Contacts a remote server to retrieve initial configuration.  It connects to Netbird, formats the HDD, creates the admin user and configures Grafana.  When complete, `/data/.kit_config` is touched so it only runs once.
For an exhaustive description see [remote-configurer.md](remote-configurer.md).

### SystemStatus
Periodically collects metrics such as hostname, router information, Netbird status and power state, storing them through `ExNVR.SystemStatus`.

### PowerSchedule
Reads schedule data from `SystemSettings` and powers off or stops pipelines when outside the configured window.
More details can be found in [power-schedule.md](power-schedule.md).

### Hardware.Power
Monitors GPIO pins for AC loss and low battery alarms and records events when they change.
The monitored pins and event handling are documented in [hardware-power.md](hardware-power.md).

### RUT.Auth
Authenticates with a Teltonika router and refreshes its session token when required.

## Application Processes

The Phoenix application in `ui/` runs additional tasks:

### TokenPruner
Deletes expired login tokens every two hours.

### SerialPortChecker
Periodically enumerates serial ports and starts `ExNVR.Hardware.Victron` workers when new ports are detected.

### SystemStatus (host)
Collects CPU, memory and block storage statistics when running on non‑Nerves targets.

### HlsStreamingMonitor
Tracks active HLS streams and stops them if no client has accessed them for roughly a minute.

### RemoteConnection
Establishes a WebSocket connection to a remote server for configuration commands and reporting health data.
See [remote-connection.md](remote-connection.md) for the protocol details.

### Device specific workers
Each camera started under `ExNVR.Devices.Supervisor` runs a set of processes:
* `DiskMonitor` – observes disk usage and removes old recordings when space gets low.
* `BIF.GeneratorServer` – builds BIF thumbnail files from hourly snapshots.
* `SnapshotUploader` – periodically uploads snapshots to a configured remote storage.
* `LPREventPuller` – fetches license plate recognition events if enabled.
* `UnixSocketServer` – (on Unix systems) exposes snapshots via a Unix domain socket.

These workers keep the recording pipelines functional and manage disk usage, snapshots and external integrations.
