defmodule NvrSupport.Watchdog.HealthCheck do
  @moduledoc """
  Polls a small set of "is the device doing its job?" checks and raises a raw
  Alarmist alarm per criterion once it has been failing for its configured
  window, then combines them into one composite alarm.

  The "must persist for N" debounce lives in this poller (tracking how long each
  criterion has been failing) rather than in Alarmist's compile-time
  `debounce/2`. That makes the windows **runtime-configurable** - a
  VM/fault-injection test can dial them down to seconds (and the poll interval
  too) over RPC without rebuilding the firmware. Only conditions a reboot can
  plausibly fix are included:

    * `StorageUnavailable`   - recordings/data partition not writable (a real
      write probe, so a read-only remount or I/O errors trip it) AND at least
      one camera is configured - an unwritable disk with nothing to record can't
      be fixed by a reboot, so it is left alone
    * `InternalUnresponsive` - core ExNVR processes stopped responding
    * `RecordingStalled`     - cameras configured but none recording

  The composite alarm (this module's own id) is what `NvrSupport.Watchdog.Heart`
  watches.

  ## Runtime configuration

      config :nvr_support,
        poll_interval_ms: :timer.seconds(30),
        storage_debounce_ms: :timer.minutes(15),
        internal_debounce_ms: :timer.minutes(5),
        recording_debounce_ms: :timer.minutes(30),
        recordings_path: "/data"

  All are read via `Application.get_env/3` on every poll, so changing them at
  runtime takes effect on the next cycle.
  """
  use GenServer
  use Alarmist.Alarm

  alias NvrSupport.Watchdog.Checks

  require Logger

  # {alarm id, config key for its debounce window, default window}
  @criteria [
    {__MODULE__.StorageUnavailable, :storage_debounce_ms, :timer.minutes(15)},
    {__MODULE__.InternalUnresponsive, :internal_debounce_ms, :timer.minutes(5)},
    {__MODULE__.RecordingStalled, :recording_debounce_ms, :timer.minutes(30)}
  ]

  @default_poll_interval :timer.seconds(30)

  # Composite alarm: set when ANY criterion alarm is set. The "must persist"
  # timing is enforced by the poller below, so the rule is a plain OR - no
  # compile-time debounce, which is what lets the windows be runtime-tunable.
  alarm_if do
    __MODULE__.StorageUnavailable or
      __MODULE__.InternalUnresponsive or
      __MODULE__.RecordingStalled
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Alarmist.add_managed_alarm(__MODULE__)
    Logger.info("[Watchdog] registered composite alarm #{inspect(__MODULE__)}")
    schedule_poll()
    # failing_since: alarm_id => monotonic ms when the criterion first started failing
    {:ok, %{failing_since: %{}}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    state = run_checks(state)
    schedule_poll()
    {:noreply, state}
  end

  @doc """
  Evaluate every criterion once. A criterion that is healthy clears its alarm
  immediately; a failing one raises its alarm only after it has stayed failing
  for its configured window. Returns the updated state (the per-criterion
  "failing since" timestamps). Exposed for tests.
  """
  @spec run_checks(map()) :: map()
  def run_checks(state \\ %{failing_since: %{}}) do
    now = System.monotonic_time(:millisecond)
    path = Application.get_env(:nvr_support, :recordings_path, "/data")

    failing_since =
      Enum.reduce(@criteria, state.failing_since, fn {alarm_id, key, default}, acc ->
        window = Application.get_env(:nvr_support, key, default)
        evaluate(alarm_id, healthy?(alarm_id, path), window, now, acc)
      end)

    %{state | failing_since: failing_since}
  end

  defp evaluate(alarm_id, true, _window, _now, acc) do
    :alarm_handler.clear_alarm(alarm_id)
    Map.delete(acc, alarm_id)
  end

  defp evaluate(alarm_id, false, window, now, acc) do
    since = Map.get(acc, alarm_id, now)
    if now - since >= window, do: :alarm_handler.set_alarm({alarm_id, []})
    Map.put(acc, alarm_id, since)
  end

  defp healthy?(__MODULE__.StorageUnavailable, path), do: Checks.storage_ok?(path)
  defp healthy?(__MODULE__.InternalUnresponsive, _path), do: Checks.internal_responsive?()
  defp healthy?(__MODULE__.RecordingStalled, _path), do: Checks.recording_ok?()

  defp schedule_poll do
    interval = Application.get_env(:nvr_support, :poll_interval_ms, @default_poll_interval)
    Process.send_after(self(), :poll, interval)
  end
end
