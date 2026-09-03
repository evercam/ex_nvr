defmodule ExNVR.Nerves.Monitoring.AutoReboot do
  @moduledoc """
  Module responsible for rebooting the device on a recurring schedule.

  The configuration lives in `ExNVR.Nerves.SystemSettings` and is made of an
  `interval` in hours (`nil` disables the feature), a `reboot_at` anchor and a
  `timezone`.

  `reboot_at` is an **anchor**, not a deadline: reboots happen at the anchor's
  local wall clock and every `interval` hours after it. Occurrences before the
  anchor never fire, so setting an anchor in the future delays the first reboot
  instead of triggering one right away.

  All the arithmetic is done on naive local time, which keeps the reboot at the
  same local time of day across DST transitions (at the cost of 23h/25h real
  intervals). A consequence is that an anchor whose time of day falls inside a
  DST spring forward gap skips that day.

  Safety invariants, in order of importance:

    * `:grace` must be greater than `:tolerance`, otherwise a reboot can
      trigger itself again right after booting.
    * at most one reboot per process lifetime, enforced by the `rebooting?`
      latch since `:tolerance` spans several ticks.
    * at most one reboot per half interval, enforced across reboots by the
      persisted `"reboot"` event.
  """

  use GenServer, restart: :transient

  require Logger

  alias ExNVR.{Devices, Events, Pipelines}
  alias ExNVR.Model.Device
  alias ExNVR.Nerves.{Application, DiskMounter, SystemSettings}
  alias ExNVR.Nerves.SystemSettings.State.AutoReboot
  alias Nerves.Runtime

  @grace to_timeout(minute: 5)
  @tick to_timeout(second: 30)
  @tolerance 120
  @flush_timeout to_timeout(second: 2)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the occurrence that's currently due, if any.

  Pure function, exposed to allow testing the schedule arithmetic with an
  injected `now`.
  """
  @spec due_occurrence(map(), NaiveDateTime.t(), non_neg_integer()) ::
          {:ok, NaiveDateTime.t()} | :not_due
  def due_occurrence(%{interval: nil}, _now, _tolerance), do: :not_due
  def due_occurrence(%{reboot_at: nil}, _now, _tolerance), do: :not_due

  def due_occurrence(%{interval: hours, reboot_at: anchor}, now, tolerance) do
    interval = hours * 60 * 60

    # `rem/2` gives the elapsed time since the last occurrence directly. A
    # negative `elapsed` means the anchor is in the future or the clock is
    # still unset (1970), in both cases nothing is due.
    case NaiveDateTime.diff(now, anchor) do
      elapsed when elapsed < 0 -> :not_due
      elapsed when rem(elapsed, interval) >= tolerance -> :not_due
      elapsed -> {:ok, NaiveDateTime.add(now, -rem(elapsed, interval))}
    end
  end

  @doc """
  Returns the next `count` occurrences, strictly after `now`.
  """
  @spec next_occurrences(map(), NaiveDateTime.t(), non_neg_integer()) :: [NaiveDateTime.t()]
  def next_occurrences(%{interval: nil}, _now, _count), do: []
  def next_occurrences(%{reboot_at: nil}, _now, _count), do: []

  def next_occurrences(%{interval: hours, reboot_at: anchor}, now, count)
      when is_integer(hours) and hours > 0 do
    interval = hours * 60 * 60

    anchor
    |> first_occurrence_after(now, interval)
    |> Stream.iterate(&NaiveDateTime.add(&1, interval))
    |> Enum.take(count)
  end

  # An interval that never passed the changeset validation has no schedule.
  def next_occurrences(_config, _now, _count), do: []

  @impl true
  def init(opts) do
    Logger.info("Starting auto reboot monitoring")
    SystemSettings.subscribe()

    state = %{
      config: get_config(),
      started_at: System.monotonic_time(:millisecond),
      grace: Keyword.get(opts, :grace, @grace),
      tick: Keyword.get(opts, :tick, @tick),
      tolerance: Keyword.get(opts, :tolerance, @tolerance),
      flush_timeout: Keyword.get(opts, :flush_timeout, @flush_timeout),
      rebooting?: false
    }

    Process.send_after(self(), :check_reboot, state.grace)
    {:ok, state}
  end

  # A reboot is already under way, ignore the queued ticks.
  @impl true
  def handle_info(:check_reboot, %{rebooting?: true} = state), do: {:noreply, state}

  @impl true
  def handle_info(:check_reboot, state) do
    Process.send_after(self(), :check_reboot, state.tick)

    case check_due(state) do
      {:due, occurrence} ->
        {:noreply, do_reboot(state, occurrence)}

      :not_due ->
        {:noreply, state}

      {:skipped, reason} ->
        Logger.warning("[AutoReboot] skipping reboot: #{reason}")
        {:noreply, state}
    end
  end

  # Deliberately not re-arming the timer here, the grace period is what keeps a
  # reboot from triggering itself again right after booting.
  @impl true
  def handle_info({:system_settings, :update}, state) do
    {:noreply, %{state | config: get_config()}}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("[AutoReboot] received unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  # The anchor is the first occurrence while it's still in the future, the
  # series never extends backwards. Same arithmetic as `due_occurrence/3`.
  defp first_occurrence_after(anchor, now, interval) do
    case NaiveDateTime.diff(now, anchor) do
      elapsed when elapsed < 0 -> anchor
      elapsed -> NaiveDateTime.add(anchor, (div(elapsed, interval) + 1) * interval)
    end
  end

  defp check_due(state) do
    with {:ok, occurrence} <- local_occurrence(state),
         :ok <- check_uptime(state),
         :ok <- check_ntp(),
         :ok <- check_last_reboot(state) do
      {:due, occurrence}
    end
  end

  defp local_occurrence(%{config: config, tolerance: tolerance}) do
    case DateTime.now(config.timezone) do
      {:ok, now} ->
        due_occurrence(config, DateTime.to_naive(now), tolerance)

      {:error, reason} ->
        {:skipped, "invalid timezone #{inspect(config.timezone)}: #{inspect(reason)}"}
    end
  end

  # Monotonic time is immune to NTP steps, unlike the wall clock.
  defp check_uptime(%{started_at: started_at, grace: grace}) do
    case System.monotonic_time(:millisecond) - started_at do
      elapsed when elapsed >= grace -> :ok
      elapsed -> {:skipped, "uptime #{elapsed}ms is below the grace period"}
    end
  end

  defp check_ntp do
    if NervesTime.synchronized?(), do: :ok, else: {:skipped, "NTP not synced"}
  end

  # Guards against a double reboot when the clock steps backwards or when the
  # anchor lands in an ambiguous DST fall back hour. Any other producer of a
  # "reboot" event also suppresses the scheduled one for half an interval,
  # which is the desired behaviour.
  defp check_last_reboot(%{config: %{interval: hours}}) do
    gap = div(hours * 60 * 60, 2)

    case Events.last_event_time("reboot") do
      nil ->
        :ok

      time ->
        elapsed = DateTime.diff(DateTime.utc_now(), time)
        if elapsed >= gap, do: :ok, else: {:skipped, "already rebooted #{elapsed}s ago"}
    end
  end

  defp do_reboot(state, occurrence) do
    Logger.info(
      "[AutoReboot] rebooting the device, scheduled occurrence " <>
        "#{occurrence} #{state.config.timezone}"
    )

    # The reboot itself must be the last thing that can be prevented, so none
    # of the preparation steps is allowed to abort it.
    safe("create reboot event", fn -> create_reboot_event(state, occurrence) end)
    safe("stop recording", &stop_recording/0)
    Process.sleep(state.flush_timeout)
    safe("unmount data disk", &DiskMounter.umount/0)

    if Application.target() != :host, do: Runtime.reboot()

    %{state | rebooting?: true}
  end

  defp create_reboot_event(state, occurrence) do
    params = %{
      type: "reboot",
      metadata: %{
        reason: "auto_reboot",
        interval: state.config.interval,
        scheduled_at: NaiveDateTime.to_iso8601(occurrence),
        timezone: state.config.timezone
      }
    }

    with {:error, changeset} <- Events.create_event(params) do
      Logger.error("[AutoReboot] failed to save the reboot event: #{inspect(changeset)}")
    end
  end

  defp stop_recording do
    Devices.list()
    |> Enum.filter(&Device.recording?/1)
    |> Enum.each(&Pipelines.Main.stop_recording/1)
  end

  # An explicit `null` pushed by the remote server nils the embed, and default
  # values are only materialized when the settings are loaded from disk.
  defp get_config, do: SystemSettings.get_settings().auto_reboot || %AutoReboot{}

  defp safe(label, fun) do
    fun.()
  catch
    kind, reason ->
      Logger.error(
        "[AutoReboot] #{label} failed: #{Exception.format(kind, reason, __STACKTRACE__)}"
      )
  end
end
