# nvr_support

Firmware-side support library for ex_nvr Nerves devices. It currently provides a
**watchdog** that reboots the device when it stops doing its job, even while the
BEAM itself is still alive.

Stock `nerves_heart` (`-heart` in `rel/vm.args.eex`) only reboots when the Erlang
runtime stops scheduling. It cannot notice that recording has wedged or the data
partition has gone read-only. This library closes that gap by driving Erlang's
`:heart` callback from [Alarmist](https://hex.pm/packages/alarmist) synthetic
alarms.

## How it works

```
NvrSupport.Watchdog.HealthCheck (polls every poll_interval_ms)
  → a criterion has failed continuously for its window → raises a raw alarm
  → composite alarm NvrSupport.Watchdog.HealthCheck sets
  → NvrSupport.Watchdog.Heart's alarm mirrors it
  → Heart's :heart callback returns :error
  → nerves_heart stops feeding the hardware watchdog → reboot
```

The watchdog only reboots for conditions a reboot can plausibly fix (storage
failures, unresponsive core processes, stalled recording). External causes such
as a camera going offline stay on the dashboard via `ExNVR.HealthReport` rather
than rebooting. The exact criteria and their windows live in the
`NvrSupport.Watchdog.HealthCheck` moduledoc.

The "must persist for N" debounce is enforced by the poller: it tracks how long
each criterion has been failing and reads the window from config on every poll,
rather than using Alarmist's compile-time `debounce/2`. That keeps the windows
**runtime-configurable**, so a VM or fault-injection test can dial them (and the
poll interval) down to seconds without rebuilding the firmware.

## Usage

Pulled in only by the Nerves firmware apps; `ui` stays agnostic. Add the dep and
start it from the firmware Application's **non-host** children:

```elixir
# nerves_fw/mix.exs / nerves_community/mix.exs
{:nvr_support, path: "../nvr_support"}

# firmware Application, non-host branch only
children = [..., {NvrSupport, []}]
```

`vm.args.eex` must keep `-heart` and add an init-handshake grace:

```
-heart -env HEART_BEAT_TIMEOUT 30
-env HEART_INIT_TIMEOUT 600
```

## Configuration

All values are read at runtime via `Application.get_env/3` on every poll, so they
can live in `config/config.exs` or `runtime.exs`, or be changed live (e.g. over
RPC from a VM test):

```elixir
config :nvr_support,
  enabled: true,                              # master switch
  poll_interval_ms: :timer.seconds(30),
  storage_debounce_ms: :timer.minutes(15),
  internal_debounce_ms: :timer.minutes(5),
  recording_debounce_ms: :timer.minutes(30),
  recordings_path: "/data"
```

For fault-injection tests, set short windows (a few seconds) and a short
`poll_interval_ms` so a failure trips the watchdog quickly. The data sources the
checks read can also be overridden so a test can hand the watchdog known states
without real hardware: `:system_status_module` (the internal-liveness probe
target), `:devices_module`, or a static `:devices` list used in place of the live
device lookup.

## Disabling at runtime (kill-switch)

Either set `config :nvr_support, enabled: false`, or flip the Nerves KV key
(survives until cleared, no rebuild):

```elixir
Nerves.Runtime.KV.put("nvr_support_disable_watchdog", "true")
```

While disabled the heart callback always reports healthy, so the device will only
reboot on true BEAM death.
