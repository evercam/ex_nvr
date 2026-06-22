defmodule NvrSupport.Watchdog.Checks do
  @moduledoc """
  The individual watchdog health checks.

  Each predicate returns `true` when **healthy** and `false` when **failing** -
  the polarity `NvrSupport.Watchdog.HealthCheck.run_checks/1` expects (healthy
  clears the alarm, failing raises it).

  All functions accept injected data/opts so they can be unit-tested without a
  running ExNVR system, and they reach ExNVR via configured module names looked
  up at runtime, so this library carries no compile-time dependency on `ui`.
  """
  require Logger

  @doc """
  True when `path` (the recordings/data partition) actually accepts a write.

  Uses a synchronous write-and-delete probe rather than `File.stat/1` so it
  catches the failure modes that matter for an NVR - a partition remounted
  read-only after errors, or I/O errors that only surface on write (e.g. a
  failing disk). `File.stat` reports the inode's permission bits, not the mount
  state, so it would miss exactly the "video writes are failing" case. The probe
  file is tiny, written with `:sync`, and removed immediately.
  """
  @spec storage_writable?(Path.t()) :: boolean()
  def storage_writable?(path) do
    probe = Path.join(path, ".nvr_watchdog_probe")

    result =
      case :file.open(probe, [:write, :raw, :sync]) do
        {:ok, fd} ->
          written = :file.write(fd, "ok")
          _ = :file.close(fd)
          written

        {:error, _reason} = error ->
          error
      end

    _ = File.rm(probe)

    case result do
      :ok ->
        true

      {:error, reason} ->
        Logger.warning("[Watchdog] storage #{inspect(path)} not writable (#{inspect(reason)})")
        false
    end
  rescue
    error ->
      Logger.warning("[Watchdog] storage probe error (#{inspect(error)})")
      false
  end

  @doc """
  True when storage is healthy *for the watchdog's purposes*: either the
  recordings path accepts writes, or no cameras are configured.

  An unwritable disk on a device with nothing to record isn't worth a reboot -
  it can't help and would just reboot-loop - so storage only counts as a fault
  once recording is intended (at least one configured camera). When cameras are
  present, this reduces to `storage_writable?/1`. `:devices` can be injected for
  tests.
  """
  @spec storage_ok?(Path.t(), keyword()) :: boolean()
  def storage_ok?(path, opts \\ []) do
    not devices_present?(opts) or storage_writable?(path)
  end

  @doc """
  True when at least one camera is configured (recording is intended).
  `:devices` can be injected for tests.
  """
  @spec devices_present?(keyword()) :: boolean()
  def devices_present?(opts \\ []) do
    Keyword.get_lazy(opts, :devices, &list_devices/0) != []
  end

  @doc """
  True when the core ExNVR state process responds.

  A `:probe` fun can be injected for tests; by default it calls
  `ExNVR.SystemStatus.get_all/0` and treats a crash/timeout/exit as
  unresponsive. When the module isn't loaded (e.g. host/tests) the check is
  considered healthy so it can never reboot a box it can't actually inspect.
  """
  @spec internal_responsive?(keyword()) :: boolean()
  def internal_responsive?(opts \\ []) do
    probe = Keyword.get(opts, :probe, &default_probe/0)
    probe.()
  catch
    :exit, reason ->
      Logger.warning("[Watchdog] internal check exited (#{inspect(reason)})")
      false

    kind, reason ->
      Logger.warning("[Watchdog] internal check failed (#{inspect(kind)}, #{inspect(reason)})")
      false
  end

  @doc """
  True when recording is NOT stalled - i.e. there are no configured cameras, or
  at least one of them is recording. `:devices` can be injected for tests.
  """
  @spec recording_ok?(keyword()) :: boolean()
  def recording_ok?(opts \\ []) do
    devices = Keyword.get_lazy(opts, :devices, &list_devices/0)
    not recording_stalled?(devices)
  end

  @doc """
  True when cameras are configured but none are in the `:recording` state - the
  whole recording pipeline appears wedged rather than a single camera being
  offline.
  """
  @spec recording_stalled?([map()]) :: boolean()
  def recording_stalled?(devices) when is_list(devices) do
    devices != [] and Enum.all?(devices, &(device_state(&1) != :recording))
  end

  ## Internal

  defp default_probe do
    mod = Application.get_env(:nvr_support, :system_status_module, ExNVR.SystemStatus)

    cond do
      not Code.ensure_loaded?(mod) -> true
      is_nil(Process.whereis(mod)) -> false
      true -> probe_responds?(mod)
    end
  end

  defp probe_responds?(mod) do
    _ = apply(mod, :get_all, [])
    true
  end

  # A static `:devices` list can be configured to override the live lookup
  # (used by tests and manual experiments to hand the watchdog known states);
  # otherwise the configured devices module is queried.
  defp list_devices do
    case Application.get_env(:nvr_support, :devices) do
      devices when is_list(devices) -> devices
      _ -> list_devices_from_module()
    end
  end

  defp list_devices_from_module do
    mod = Application.get_env(:nvr_support, :devices_module, ExNVR.Devices)

    if Code.ensure_loaded?(mod) and function_exported?(mod, :list, 0) do
      apply(mod, :list, [])
    else
      []
    end
  rescue
    error ->
      Logger.warning("[Watchdog] device list failed (#{inspect(error)})")
      []
  catch
    :exit, reason ->
      Logger.warning("[Watchdog] device list exited (#{inspect(reason)})")
      []
  end

  defp device_state(%{state: state}), do: state
  defp device_state(device) when is_map(device), do: Map.get(device, :state)
  defp device_state(_), do: nil
end
