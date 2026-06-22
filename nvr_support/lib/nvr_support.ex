defmodule NvrSupport do
  @moduledoc """
  Firmware-side watchdog support for ex_nvr Nerves devices.

  Starts a small supervision subtree that drives Erlang's `:heart` callback from
  Alarmist synthetic alarms, so the device reboots when it stops doing its job
  (recording wedged, storage read-only, core processes unresponsive) even while
  the BEAM is still scheduling. See `NvrSupport.Watchdog.HealthCheck` and
  `NvrSupport.Watchdog.Heart` for the full chain, and the README for the design.

  Pulled in only by the Nerves firmware projects (`nerves_fw`,
  `nerves_community`); the `ui` app stays agnostic so it can still run on a
  non-Nerves host. Start it from a firmware Application's **non-host** children:

      children = [..., {NvrSupport, []}]
  """
  use Supervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl Supervisor
  def init(_opts) do
    children = [
      {NvrSupport.Watchdog.HealthCheck, []},
      {NvrSupport.Watchdog.Heart, []}
    ]

    # rest_for_one: HealthCheck owns the composite alarm that Heart's rule
    # depends on, so if the poller restarts, restart Heart after it to rebuild
    # its subscription/registration cleanly.
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
