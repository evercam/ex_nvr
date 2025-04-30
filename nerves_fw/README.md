# ExNVR Nerves

Nerves firmware for `ex_nvr`.

## Supported Platforms

The current supported platforms are:

| Platform | Description |
|----------|-------------|
| [ExNVRSystemRpi4](https://github.com/evercam/ex_nvr_system_rpi4) | Custom Raspberry Pi 4 image based on the official nerves image |
| [ExNVRSystemRpi5](https://github.com/evercam/ex_nvr_system_rpi5) | Custom Raspberry Pi 5 image based on the official nerves image |

## Usage

This nerves image is tailored for [Evercam](https://evercam.io/) use case. So it should be used as an example for anyone who wants to create an `ex_nvr` nerves image for his own usage.

### Dependencies

In Evercam, we use [netbird](https://github.com/netbirdio/netbird). So we include the binary directly in the nerves image as it is easier than creating a busybox or buildroot config to install them.

The mix task `firmware.deps` is responsible for downlading the dependencies.

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
