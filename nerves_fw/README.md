# ExNVR Nerves

Nerves firmware for `ex_nvr`.

This Nerves image is tailored for [Evercam](https://evercam.io/) use case, used in real-life as the software layer controlling our production Kits deployed in construction sites aroud the world.

It can be used as an example for anyone who wants to create an `ex_nvr` nerves image for their own device / use case.

The current supported platforms are:

| Platform | Description |
|----------|-------------|
| [ExNVRSystemRpi4](https://github.com/evercam/ex_nvr_system_rpi4) | Custom Raspberry Pi 4 image based on the official nerves image |
| [ExNVRSystemRpi5](https://github.com/evercam/ex_nvr_system_rpi5) | Custom Raspberry Pi 5 image based on the official nerves image |

# Overview
The ExNVR Nerves firmware packages the [core ExNVR app](https://github.com/evercam/ex_nvr/tree/master/ui) with the Nerves embedded Linux platform.
It provides a complete solution for deploying / configuring / updating an ExNVR on a Raspberry Pi hardware.

# Features
- Hardware integration (GPIO, disk mounting, etc.)
- Remote configuration via cloud API
- System monitoring and power management
- Network connectivity (including VPN via Netbird)
- Firmware updates over-the-air via NervesHub

# Architecture
```
nerves_fw/
├── config/              # Configuration for different environments
├── lib/                
│   └── nerves_fw/      
│     ├── giraffe/       # Custom hardware configuration (Giraffe board)
│     ├── grafana_agent/ # Grafana agent setup & management
│     ├── hardware/      # Hardware modules (Power)
│     ├── health/        # System health monitoring
│     ├── monitoring/    # Power scheduling/management
│     ├── netbird/       # Netbird VPN client
│     ├── rut/           # Router (Teltonika) integration (auth, scheduling)
│     ├── application.ex    # OTP application entrypoint
│     ├── disk_mounted.ex   # Module for mounting hard drives on `fstab` file
│     ├── grafana_agent.ex  # Grafana agent GenServer
│     ├── disk_mounted.ex   # Module for mounting hard drives on `fstab` file
│     ├── remote_configurer.ex      # Remote configuration client
│     ├── remote_config_handler.ex  # Handles remote configuration changes
│     └── system_status.ex  # System status inforation collector 
├── priv/                
│   └── grafana_agent/   # Grafana agent configuration template
└── rootfs_overlay/      # Files to be copied into Linux rootfs
    ├── nginx/           # NGINX configuration
    └── iex.exs          # IEx shell initialization for NervesHub
```

# ExNVR firmware life-cycle
## 1. Boot Process
Here's is what happens when an ExNVR device boots:

### 1. Nerves Runtime Initialization
When power is applied to the device:

1- The Nerves runtime (nerves_runtime) is started early in the boot process and mounts file systems (read-only root, writable /data partition) then initializes the hardware and starts the Erlang VM.

### 2. Application Startup
Once the Nerves runtime is initialized:

- Tha app entrypoint `ExNVR.Nerves.Application.start/2` is called
- The application checks which target platform it's running on (ex_nvr_rpi4, ex_nvr_rpi5, or giraffe)
- The OTP supervision tree is constructed based on target-specific requirements
- Database migrations are automatically applied via ExNVR.Release.migrate()
- Common supervisors and GenServers are started (DiskMounter, SystemStatus, etc.)
- All services start in parallel but with dependencies managed via the supervision tree


### 3.Hardware-Specific Initialization

Depending on the target platform:

A- For **giraffe** hardware:

**ExNVR.Nerves.Giraffe.Init** GenServer is started
- `GPIO16` is set to `HIGH` to power on the HDD
- `GPIO26` is set to `HIGH` to power on the PoE circuitry
Once initialization completes, the GenServer terminates normally


B- For standard **Raspberry Pi** (Evercam) targets:

The **ExNVR.Nerves.Hardware.Power** module is started via DynamicSupervisor
It retrieves system settings to determine if power monitoring is enabled
GPIO pins for power monitoring are configured:
- **AC Power** Pin (`GPIO23`) - Monitors AC power status
Value `0` indicates AC power **failure**
Value `1` indicates AC power is **OK**

- **Battery** Pin (`GPIO16`) - Monitors battery status
Value `1` indicates battery level is **low**
Value `0` indicates battery level is **OK**
- 

**Event Generation**
When a state change is detected and confirmed (after debouncing), an event is created in the system with the appropriate type

`power` for AC power state changes
`low-battery` for battery state changes

**Actions**
Based on the how the power schedule is configured (via the remote configurer), the system can take different actions:

1- The PowerSchedule module can trigger actions such as:
- `poweroff`  Safely shut down the device
- `stop_pipeline`  Stop all recording devices but keep the system running

# TODO - continue here

### 2. Device Configuration
The device can be configured through several mechanisms:

Remote Configuration: On first boot, the device contacts a cloud endpoint to fetch its initial configuration (VPN setup, hard drive formatting, user credentials)
Local Configuration: Through the ExNVR werb UI
Command Line: Via SSH access (enabled by Nerves SSH)

### Development
In Evercam, we use [netbird](https://github.com/netbirdio/netbird). So we include the binary directly in the nerves image as it is easier than creating a busybox or buildroot config to install them.

The mix task `firmware.deps` is responsible for downloading the dependencies.

### Env variables
We need to provide the environment variables at compile time. Create a `.env` file (you can check `.env.sample` for the needed env variables) and fill 
the values.

### Building a firmware

To create a firmware, run
```bash
source .env
mix deps.get
mix firmware
```
