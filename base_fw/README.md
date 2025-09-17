# ExNVR Nerves Image

A nerves firmware for ExNVR.

## Supported Platforms

The current supported platforms are:

| Platform | Description |
|----------|-------------|
| [rpi4](https://github.com/evercam/ex_nvr_system_rpi4) | Custom Raspberry Pi 4 image based on the official nerves image |
| [rpi5](https://github.com/evercam/ex_nvr_system_rpi5) | Custom Raspberry Pi 5 image based on the official nerves image |

## Getting Started

To start your Nerves app:
  * `export MIX_TARGET=my_target` or prefix every command with
    `MIX_TARGET=my_target`. For example, `MIX_TARGET=rpi4`
  * Install dependencies with `mix deps.get`
  * Create firmware with `mix firmware`
  * Burn to an SD card with `mix burn`
