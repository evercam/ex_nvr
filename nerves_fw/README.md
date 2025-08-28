# ExNVR Nerves firmware

## What it does

* Boots a Raspberry Pi into a read‑only Nerves system with a persistent `/data` partition.
* Starts ExNVR and a set of services that handle networking, storage, telemetry, remote configuration, and power control.
* Applies an optional first‑time “remote configuration” from the cloud (VPN join, disk format/mount, admin user, telemetry).
* Continuously enforces a power schedule and responds to UPS signals to protect recordings and the filesystem.
* Surfaces health and metrics (including optional logs) upstream.

> Key persistent locations: `/data/settings.json` (system settings) and `/data/media` (recordings, when a disk is mounted).

---


## Defaults at a glance

| Area                    | Default                                          |
| ----------------------- |--------------------------------------------------|
| Timezone                | UTC                                              |
| Action outside schedule | Power off                                        |
| UPS enabled             | false                                            |
| UPS pins                | AC: `GPIO27`, Low‑battery: `GPIO22`              |
| UPS actions             | AC fail: `nothing`; Low‑battery: `stop_recording` |
| UPS delay               | 120 s                                            |
| Mountpoint              | `/data/media`             |
| Settings file           | `/data/settings.json`                            |
| NetBird state           | `/data/netbird`                                  |
| Grafana Agent           | `/data/grafana_agent/agent.yml`                  |


---

## High‑level components

* **System Settings service**: Reads/writes a JSON settings file with three sections: **power schedule**, **router** (credentials for the Teltonika), and **UPS** (GPIO pins, actions, and delays). Broadcasts changes to interested services.
* **Disk Mounter**: Manages `/data/fstab` and mounts/unmounts disks by UUID. Reacts to kernel block‑device events.
* **Remote Configurer**: One‑time configuration pulled from a cloud endpoint; performs VPN join, formats/mounts storage, creates an ExNVR admin, and configures telemetry.
* **NetBird**: Always‑on VPN daemon with a client wrapper for `up`, `down`, and `status`. State lives under `/data/netbird`.
* **Grafana Agent**: Runs as a supervised process. Generates its config in `/data/grafana_agent/agent.yml`, and can push metrics and (optionally) logs.
* **Router (RUT) integration**: Authenticates to the Teltonika via the LAN default gateway, reads device info/IO status, and can configure the router’s IO scheduler to mirror the local schedule.
* **Power Schedule monitor**: Enforces allowed run windows; outside the window it either powers down the kit or stops recordings.
* **UPS monitor**: Watches two GPIO lines (AC OK and Low Battery) with debounce and a configurable action delay. Stops/starts recordings or powers off as configured.
* **System Status**: Periodically publishes host/router/VPN/UPS markers and pushes an hourly recordings “runs summary”.
* **Nginx reverse proxy**: Listens on port 80 and exposes a convenience path to proxy requests to internal services (with WebSocket upgrades).

---

## Boot sequence (what happens from power‑on)

On power:

1. **Nerves boots**
   A minimal Linux + Erlang/Elixir runtime starts. Root is read‑only; `/data` is writable and persistent. Networking, time sync, and basic services come online.

2. **ExNVR application starts**

   * Database migrations for ExNVR run once at startup.
   * The supervision tree is built. On embedded targets (RPi4/5 and “giraffe”), the following groups start:

     * PubSub and System Settings service.
     * Common services: NetBird, Disk Mounter, Grafana Agent, Nginx, Remote Configurer (with its configured endpoint), Power Schedule monitor, Router Auth, and System Status.
     * On embedded targets (not host), the **UPS monitor** also starts.
     * Target‑specific children may start on special builds (e.g., “giraffe”).

3. **First‑boot remote configuration (if not already completed)**
   The Remote Configurer checks a cloud endpoint using the kit’s ID. If configuration is available:

   * **VPN**: Joins the NetBird management server with the provided setup key (uses the kit ID as the hostname).
   * **Storage**: Detects the first unformatted drive, wipes existing partitions, creates a single partition, and creates an ext4 filesystem. Creates `/data/media`, marks it immutable, and adds an fstab entry by UUID so the Disk Mounter can mount it automatically.
   * **ExNVR admin**: Removes the default local admin if present and ensures `admin@evercam.io` exists with the provided password.
   * **Telemetry**: Rewrites the Grafana Agent config with Prometheus and Loki credentials/URLs and restarts the agent to pick it up.
   * **Finalization**: Posts device identity (MAC, serial, platform), and the ExNVR admin credentials back to the endpoint, drops a marker file under `/data` to skip future runs, and exits.
   * If the endpoint responds “already configured”, it simply exits. If there are transient errors, it retries in a short loop.

4. **Steady state**

   * **Disk Mounter** mounts any fstab‑listed filesystems; logs a warning if mounting fails. It listens for hot‑plug events to keep mounts up to date.
   * **Grafana Agent** runs and ships metrics (and logs if configured).
   * **NetBird** runs continuously; the client can return status to System Status.
   * **Router integration** authenticates against the Teltonika (based on the current default gateway), reads info, and is available for schedule sync.
   * **Power Schedule monitor** begins checking the schedule; **UPS monitor** begins watching GPIOs; **System Status** pushes markers and a periodic runs summary.

---

## What happens during boot and runtime

* **Powering the kit on**
  Triggers the boot sequence above. The first boot may take longer because of the one‑time remote configuration and telemetry setup.

* **Connecting a new USB/SATA drive**
  The kernel announces a new block device. The Disk Mounter notices the event and attempts to mount all filesystems listed in `/data/fstab`.

  * If the drive was already formatted and its UUID is in `/data/fstab`, it mounts automatically under `/data/media` (or the configured mountpoint).
  * If the drive is truly new and unformatted, only the first‑boot Remote Configurer auto‑formats it. Later replacements require either updating `/data/fstab` (by UUID) or re‑running your provisioning flow to format and register the disk.

* **Router present on the LAN**
  Router information and IO status are collected for System Status. When the local **power schedule** changes, the firmware also pushes an IO scheduler configuration to the Teltonika so the router’s digital outputs/relay follow the same windows (details below).

* **UPS state changes**
  GPIO edges for AC or Low‑Battery are debounced. If the state is stable, the configured action is executed after a configurable delay to avoid flapping.

---

## Default configuration (on a fresh system)

Settings live in `/data/settings.json` (path can be overridden). Defaults:

* **Power schedule**

  * **Timezone**: `UTC`.
  * **Action outside schedule**: `power_off` (device powers down when outside allowed windows).
  * **Schedule**: empty (no allowed windows means the schedule monitor will not trigger until you define one).

* **Router**

  * **Username/password**: empty. Without valid credentials, router info and scheduler updates will not be applied.

* **UPS**

  * **Enabled**: `false`.
  * **AC OK pin**: `GPIO27`.
  * **Low‑battery pin**: `GPIO22`.
  * **Action on AC failure**: `nothing`.
  * **Action on Low‑battery**: `stop_recording`.
  * **Action delay**: `120` seconds.
  * **Validation rules**: AC and battery pins must differ; you cannot set both actions to `stop_recording`.

* **NetBird**

  * State directory under `/data/netbird`. The service is running, but it won’t join a network until `up` is performed (typically by the Remote Configurer on first boot).

* **Grafana Agent**

  * Config and WAL directory under `/data/grafana_agent`.
  * Uses device identity (MAC, serial, platform, kit ID) to label metrics/logs.
  * Loki shipping is only enabled if both a kit ID and Loki settings are present.

* **Nginx**

  * Listens on port 80.
  * Provides a “/service/host-or-ip/…” proxy that forwards HTTP and WebSocket traffic to internal services.

---

## Power schedule

* The schedule is a weekly set of time windows per weekday, interpreted in the configured timezone.
* The monitor waits for NTP to report that time is synchronized. If time isn’t synced yet, checks are skipped and re‑attempted shortly after.
* **Inside allowed windows**: The device remains fully operational.
* **Outside allowed windows**:

  * If the configured action is **power off**, the system:

    * Emits a `shutdown` event,
    * Stops all active recordings,
    * Unmounts filesystems (lazy unmount to avoid blocking),
    * Powers off the device.
  * If the action is **stop recording**, the system:

    * Stops all active recordings,
    * Unmounts storage after a short grace period to let pipelines flush,
    * Keeps the device up.
* The monitor re‑checks every few seconds and will resume normal recording when back inside the window (mounting the storage first).

### Router IO scheduler (Teltonika)

* When the power schedule changes (for example, via a remote config message), the firmware computes router scheduler instances that match the same weekly windows and pushes them to the Teltonika.
* The router’s digital outputs considered are `dout1` and `relay0`. The current state of these pins is read first:

  * If a pin is currently “on”, the schedule is applied as‑is.
  * If it’s “off”, an inverted version of the schedule is generated so the router toggles at the opposite times.
* End times are expanded by one minute when sent to the router so that window ends are inclusive in practice.

---

## UPS behavior (battery & AC monitoring)

* Two GPIO inputs are monitored: **AC OK** and **Low Battery**. Either can be wired high/low.
* Changes are **debounced** to ignore contact bounce or short spikes.
* After a stable change, the configured action is executed **after the configured delay** (“Trigger After”) to avoid flapping.

  * **AC failure**:

    * **Power off** → stop recordings, unmount, power down.
    * **Stop recording** → stop and unmount; when AC returns, the system remounts and restarts recordings.
    * **Nothing** → only an event is recorded.
  * **Low battery**:

    * Same action options. If set to **stop recording**, recordings halt while low battery is active and automatically resume when the signal clears.
* **Auto‑enable**: If UPS monitoring is disabled but either pin reads “active” at runtime, the system auto‑enables UPS monitoring and persists that change to settings.
* Every transition emits an event with the new state so you have an audit trail.

---

## Storage behavior

* The **Disk Mounter** keeps `/data/fstab` as the source of truth. It mounts everything listed there and unmounts on demand.
* When a block device appears or disappears, it re‑invokes the mount logic. Removals also emit a `disk` event.
* **Unmounting** is lazy by default to avoid blocking any remaining IO during shutdown or stop‑recording actions.
* **First‑time formatting** is only performed by the Remote Configurer. In normal operation you add drives by formatting them externally, then adding an entry (by UUID) to the persistent fstab.

---

## Telemetry & health

* **System Status** publishes:

  * Hostname (kit ID if set), device model, and a Nerves marker.
  * Router device information and firmware (if credentials are valid).
  * NetBird status (or an error marker if not logged in).
  * UPS state (if monitoring is enabled).
* An hourly **runs summary** of recordings is calculated and pushed to the remote backend.
* **Grafana Agent**:

  * Runs from `/data/grafana_agent`; if the binary isn’t present, it is downloaded on device from the official release feed (AR.
  * Scrapes/pushes metrics to the configured Prometheus endpoint.
  * Optionally ships logs to Loki when the kit has a valid ID and credentials.
* **Nginx** proxies requests to internal services using the `/service/<address>/…` pattern and supports WebSocket upgrades. Access and error logs go to standard output.

---

## (WIP) Important notes

* **Persistence**: Only `/data/**` survives reboots and firmware updates. Anything else should be treated as ephemeral.
* **Time sync matters**: The schedule monitor won’t enforce until NTP synchronization succeeds. Make sure the kit can reach an NTP source.
* **Router credentials**: Without Teltonika credentials in settings, router info and IO scheduling won’t work. The rest of the kit still runs.
* **UPS wiring**: Ensure the configured pins match your hardware. The system prevents using the same pin for both signals and disallows selecting `stop_recording` for both actions simultaneously.
* **Graceful stop/start of recordings**: The firmware always gives recordings a short window to flush before unmounting, and remounts before resuming.
* **First‑boot vs later boots**: Automatic disk formatting and user creation are first‑boot behaviors driven by the Remote Configurer. Later disk swaps require adding the new disk’s UUID to the persistent fstab.

