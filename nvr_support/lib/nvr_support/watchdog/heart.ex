defmodule NvrSupport.Watchdog.Heart do
  @moduledoc """
  Drives Erlang's `:heart` callback from the watchdog's composite health alarm.

  When the composite `NvrSupport.Watchdog.HealthCheck` alarm sets (a criterion
  has stayed failing for its configured, runtime-tunable window - see
  `HealthCheck`), this GenServer's own alarm sets, the cached health flips to
  `:error`, and the next `:heart` callback returns `:error` - so `nerves_heart`
  stops feeding the hardware watchdog and the device reboots.

  Safeguards:

    * a runtime kill-switch (`config :nvr_support, enabled: false` or the
      `nvr_support_disable_watchdog` Nerves.Runtime.KV key) forces the callback
      to report healthy;
    * registration is defensive - if the platform's `nerves_heart` lacks
      callback support, it logs and degrades to BEAM-liveness-only rather than
      boot-looping, while still completing the init handshake.
  """
  use GenServer
  use Alarmist.Alarm

  alias NvrSupport.Watchdog.HealthCheck

  require Logger

  # Top-level heart alarm: mirrors the composite health alarm. The "must persist"
  # timing lives in HealthCheck's poller (runtime-configurable), so no debounce here.
  alarm_if do
    HealthCheck
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Called periodically by Erlang's heart to verify application health."
  @spec check() :: :ok | :error
  def check do
    GenServer.call(__MODULE__, :check)
  catch
    kind, value ->
      Logger.error("[Watchdog] heart check call failed (#{inspect(kind)}, #{inspect(value)})")
      :error
  end

  @impl GenServer
  def init(_opts) do
    register_heart_callback()

    Alarmist.add_managed_alarm(__MODULE__)
    Alarmist.subscribe(__MODULE__)

    # Tell nerves_heart the callback is registered and alarms are ready. Always
    # call this (even after a degraded registration) so HEART_INIT_TIMEOUT can
    # never boot-loop us.
    notify_init_complete()

    # Healthy until an alarm proves otherwise.
    {:ok, :ok}
  end

  @impl GenServer
  def handle_call(:check, _from, state) do
    reply = if disabled?(), do: :ok, else: state
    {:reply, reply, state}
  end

  @impl GenServer
  def handle_info(%Alarmist.Event{id: __MODULE__, state: :set}, _state) do
    Logger.error(
      "[Watchdog] health alarm raised - device deemed unhealthy; it will reboot unless it recovers"
    )

    {:noreply, :error}
  end

  def handle_info(%Alarmist.Event{id: __MODULE__, state: :clear}, _state) do
    Logger.warning("[Watchdog] health alarm cleared - device healthy again")
    {:noreply, :ok}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  ## Internal

  defp disabled? do
    Application.get_env(:nvr_support, :enabled, true) == false or kv_disabled?()
  end

  defp kv_disabled? do
    kv = Nerves.Runtime.KV

    Code.ensure_loaded?(kv) and function_exported?(kv, :get, 1) and
      apply(kv, :get, ["nvr_support_disable_watchdog"]) in ["true", "1"]
  end

  defp register_heart_callback do
    case :heart.set_callback(__MODULE__, :check) do
      :ok ->
        Logger.info("[Watchdog] heart callback registered")

      other ->
        Logger.error(
          "[Watchdog] heart.set_callback returned #{inspect(other)} - degraded to liveness-only"
        )
    end
  catch
    kind, reason ->
      Logger.error(
        "[Watchdog] heart.set_callback unavailable (#{inspect(kind)}, #{inspect(reason)}) - " <>
          "degraded to liveness-only"
      )
  end

  defp notify_init_complete do
    heart = Nerves.Runtime.Heart

    if Code.ensure_loaded?(heart) and function_exported?(heart, :init_complete, 0) do
      apply(heart, :init_complete, [])
    end
  catch
    kind, reason ->
      Logger.warning(
        "[Watchdog] Nerves.Runtime.Heart.init_complete failed (#{inspect(kind)}, #{inspect(reason)})"
      )
  end
end
