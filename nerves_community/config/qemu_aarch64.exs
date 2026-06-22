import Config

# QEMU resilience-testing target. Only built for VM fault-injection tests, never
# shipped to hardware, so it is configured differently from rpi4/rpi5.

# Boot the guest as an Erlang :peer node controlled over the serial console via
# peer_bridge (it appends `-user peer`), so VM tests can RPC into the running
# ex_nvr guest instead of using an interactive IEx console. The fixed binary
# path is created by install_peer_bridge/1 in mix.exs. This merges with the
# :erlinit config from target.exs (update_clock).
#
# Build with EXNVR_QEMU_DEBUG=1 to skip peer mode and log to the serial console
# instead - useful for watching the boot (e.g. /data formatting, app startup).
if System.get_env("EXNVR_QEMU_DEBUG") in ["1", "true"] do
  config :logger, backends: [:console]
  config :logger, :console, level: :debug
else
  config :nerves, :erlinit, alternate_exec: "/srv/erlang/bin/peer_bridge"
end

# Short watchdog windows so an injected fault trips a reboot in seconds rather
# than minutes. Tests can still override these live over RPC. recordings_path
# points at tmpfs so the watchdog is healthy at boot regardless of the data
# partition layout - tests repoint it at the storage they intend to fault.
config :nvr_support,
  poll_interval_ms: 500,
  storage_debounce_ms: 3_000,
  internal_debounce_ms: 3_000,
  recording_debounce_ms: 3_000,
  recordings_path: "/tmp"
