defmodule ExNVR.Nerves.Monitoring.UPSResilienceTest do
  @moduledoc """
  Resilience coverage for `ExNVR.Nerves.Monitoring.UPS`:

    * a GPIO open failure must degrade to disabled monitoring instead of raising
      in `init/1` and crash-looping the firmware supervisor (UPS is a direct child
      of the top-level one_for_one supervisor, so its crash-loop can take the whole
      firmware app down),

    * a degraded UPS must re-open the pins on a calm retry once they are available,
      and

    * the configured alarm action (power-off) must fire on a sustained fault and
      debounce a transient one, and AC and battery must keep independent action
      timers so one alarm can't cancel the other's pending shutdown.
  """
  use ExNVR.DataCase, async: false

  import ExUnit.CaptureLog
  import Mimic

  alias ExNVR.Nerves.GPIO
  alias ExNVR.Nerves.Monitoring.UPS
  alias ExNVR.Nerves.{DiskMounter, SystemSettings}

  @moduletag capture_log: true

  setup :set_mimic_global
  setup :verify_on_exit!

  setup_all do
    Enum.each([GPIO, DiskMounter, Nerves.Runtime], &Mimic.copy/1)

    # SystemSettings reads its path at init, so point it at a writable temp file
    # and restart it once for the whole module. Killing it per-test would burn
    # the top-level supervisor's restart budget and take the app down.
    path = Path.join(System.tmp_dir!(), "ups_resilience_settings.json")
    File.rm(path)
    Application.put_env(:ex_nvr_fw, :system_settings_path, path)
    restart_system_settings()
    on_exit(fn -> File.rm(path) end)

    :ok
  end

  describe "GPIO open failure" do
    setup do
      # Simulate the GPIO subsystem being unavailable.
      stub(GPIO, :start_link, fn _opts -> {:error, :gpio_unavailable} end)
      :ok
    end

    test "init degrades to disabled monitoring when GPIO pins cannot be opened" do
      {:ok, _settings} = enable_ups(ac_failure_action: "nothing", trigger_after: 0)

      logs =
        capture_log(fn ->
          pid = start_link_supervised!({UPS, []})

          # A synchronous call only returns if init AND the :trigger_action
          # continue ran without crashing. Before the fix the `{:ok, _} =
          # GPIO.start_link(...)` match raised and start_link_supervised! blew up.
          assert %{ac_ok: true, low_battery: false} = UPS.state(pid)
          assert Process.alive?(pid)
        end)

      assert logs =~ "monitoring disabled"
    end

    test "init survives GPIO failure on the auto-enable path (disabled in settings)" do
      {:ok, _settings} = SystemSettings.update_ups_settings(%{enabled: false})

      # maybe_enable_ups/1 must not call GPIO.value(nil) when no pin was opened.
      pid = start_link_supervised!({UPS, []})

      assert Process.alive?(pid)
      refute UPS.state(pid)
    end

    test "a settings update re-init survives GPIO failure without crashing" do
      {:ok, _settings} = enable_ups(ac_failure_action: "nothing", trigger_after: 0)

      pid = start_link_supervised!({UPS, []})
      assert Process.alive?(pid)

      # Drives the {:system_settings, :update} handler: clean_state/1 must tolerate
      # the nil pids and the re-open must degrade again rather than crash.
      {:ok, _settings} = SystemSettings.update_ups_settings(%{trigger_after: 5})

      # Processed after the update message (mailbox order), so it only returns if
      # the update handler didn't crash the process.
      assert %{ac_ok: true, low_battery: false} = UPS.state(pid)
      assert Process.alive?(pid)
    end
  end

  describe "alarm actions" do
    setup do
      test_pid = self()
      stub(Nerves.Runtime, :poweroff, fn -> send(test_pid, :poweroff) end)
      stub(DiskMounter, :mount, fn -> :ok end)
      stub(DiskMounter, :umount, fn -> :ok end)

      # Two fake "pins" backed by an Agent we can flip, so we can drive debounced
      # pin changes directly (no 1s real-GPIO debounce) and control timing.
      ac_pid = spawn_fake_pin()
      bat_pid = spawn_fake_pin()

      {:ok, values} = Agent.start_link(fn -> %{ac_pid => 1, bat_pid => 0} end)
      on_exit(fn -> if Process.alive?(values), do: Agent.stop(values) end)

      stub(GPIO, :start_link, fn opts ->
        case opts[:pin] do
          "pair_0_1" -> {:ok, ac_pid}
          "pair_2_1" -> {:ok, bat_pid}
        end
      end)

      stub(GPIO, :value, fn pin -> Agent.get(values, &Map.get(&1, pin, 0)) end)

      # ac_pin_default 1 / battery_pin_default 0: AC normal = 1 (failure = 0),
      # battery normal = 0 (low = 1). trigger_after must be > 0 to have a window.
      {:ok, _settings} = enable_ups(ac_failure_action: "power_off", trigger_after: 1)

      %{ac_pid: ac_pid, bat_pid: bat_pid, values: values}
    end

    test "powers off after a sustained AC failure past trigger_after",
         %{ac_pid: ac_pid, values: values} do
      ups = start_link_supervised!({UPS, []})

      change_pin(values, ups, ac_pid, 0)

      assert_receive :poweroff, 2_000
    end

    test "does not power off when AC recovers within trigger_after",
         %{ac_pid: ac_pid, values: values} do
      ups = start_link_supervised!({UPS, []})

      change_pin(values, ups, ac_pid, 0)
      Process.sleep(200)
      change_pin(values, ups, ac_pid, 1)

      refute_receive :poweroff, 1_500
    end

    test "a battery change does not cancel a pending AC poweroff",
         %{ac_pid: ac_pid, bat_pid: bat_pid, values: values} do
      ups = start_link_supervised!({UPS, []})

      # AC fails -> arms the AC poweroff timer (trigger_after: 1s).
      change_pin(values, ups, ac_pid, 0)
      Process.sleep(200)

      # A battery blip within the window must not touch the AC timer. With the old
      # single shared timer this cancelled the pending poweroff, so the box never
      # shut down on AC loss.
      change_pin(values, ups, bat_pid, 1)

      assert_receive :poweroff, 2_000
    end
  end

  describe "retry after GPIO failure" do
    setup do
      test_pid = self()
      stub(Nerves.Runtime, :poweroff, fn -> send(test_pid, :poweroff) end)
      stub(DiskMounter, :mount, fn -> :ok end)
      stub(DiskMounter, :umount, fn -> :ok end)

      ac_pid = spawn_fake_pin()
      bat_pid = spawn_fake_pin()

      {:ok, values} = Agent.start_link(fn -> %{ac_pid => 1, bat_pid => 0} end)
      on_exit(fn -> if Process.alive?(values), do: Agent.stop(values) end)

      # GPIO starts unavailable; flip this to let a retry succeed.
      {:ok, available} = Agent.start_link(fn -> false end)
      on_exit(fn -> if Process.alive?(available), do: Agent.stop(available) end)

      stub(GPIO, :start_link, fn opts ->
        if Agent.get(available, & &1) do
          case opts[:pin] do
            "pair_0_1" -> {:ok, ac_pid}
            "pair_2_1" -> {:ok, bat_pid}
          end
        else
          {:error, :gpio_unavailable}
        end
      end)

      stub(GPIO, :value, fn pin -> Agent.get(values, &Map.get(&1, pin, 0)) end)

      # short, deterministic retry interval for the test
      prev = Application.get_env(:ex_nvr_fw, :ups_open_retry_interval)
      Application.put_env(:ex_nvr_fw, :ups_open_retry_interval, 50)
      on_exit(fn -> restore_env(:ups_open_retry_interval, prev) end)

      {:ok, _settings} = enable_ups(ac_failure_action: "power_off", trigger_after: 1)

      %{ac_pid: ac_pid, values: values, available: available}
    end

    test "re-establishes monitoring once the GPIO pins become available",
         %{ac_pid: ac_pid, values: values, available: available} do
      {_ups, logs} =
        with_log(fn ->
          ups = start_link_supervised!({UPS, []})

          # boots degraded, then the GPIO subsystem comes back
          Agent.update(available, fn _ -> true end)
          # let the calm retry re-open the pins
          Process.sleep(250)

          # monitoring is live again: a real AC failure now drives the poweroff,
          # which only happens if the pins were actually re-opened
          change_pin(values, ups, ac_pid, 0)
          assert_receive :poweroff, 2_000
          ups
        end)

      assert logs =~ "monitoring disabled"
      assert logs =~ "re-established"
    end
  end

  defp enable_ups(opts) do
    SystemSettings.update_ups_settings(%{
      enabled: true,
      trigger_after: Keyword.fetch!(opts, :trigger_after),
      ac_failure_action: Keyword.fetch!(opts, :ac_failure_action),
      low_battery_action: "nothing",
      ac_pin: "pair_0_1",
      battery_pin: "pair_2_1"
    })
  end

  # Simulate a debounced pin change: update the backing value then deliver the
  # message the real GPIO process would send to UPS.
  defp change_pin(values, ups, pin, value) do
    Agent.update(values, &Map.put(&1, pin, value))
    send(ups, {pin, value})
  end

  defp spawn_fake_pin do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(pid, :kill) end)
    pid
  end

  defp restore_env(key, nil), do: Application.delete_env(:ex_nvr_fw, key)
  defp restore_env(key, value), do: Application.put_env(:ex_nvr_fw, key, value)

  defp restart_system_settings do
    old = Process.whereis(SystemSettings)
    Process.exit(old, :kill)

    # Wait for the supervisor to restart it with the new path before continuing.
    wait_until(fn ->
      case Process.whereis(SystemSettings) do
        nil -> false
        pid -> pid != old and Process.alive?(pid)
      end
    end)
  end

  defp wait_until(fun, retries \\ 50) do
    cond do
      fun.() -> :ok
      retries == 0 -> raise "timed out waiting for condition"
      true -> Process.sleep(10) && wait_until(fun, retries - 1)
    end
  end
end
