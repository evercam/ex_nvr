defmodule ExNVR.Nerves.Monitoring.AutoRebootTest do
  @moduledoc false
  use ExNVR.DataCase, async: false

  import ExUnit.CaptureLog
  import Mimic

  alias ExNVR.Events
  alias ExNVR.Nerves.{DiskMounter, SystemSettings}
  alias ExNVR.Nerves.Monitoring.AutoReboot

  @moduletag :tmp_dir
  @moduletag capture_log: true

  @tolerance 120
  @opts [grace: 0, tick: to_timeout(millisecond: 50), tolerance: @tolerance, flush_timeout: 0]

  setup :set_mimic_global
  setup :verify_on_exit!

  setup_all do
    Mimic.copy(DiskMounter)
    Mimic.copy(NervesTime)
    Mimic.copy(Nerves.Runtime)
    :ok
  end

  setup %{tmp_dir: tmp_dir} do
    start_supervised!({SystemSettings, [path: Path.join(tmp_dir, "settings.json")]})
    # `synchronized?/0` is always false on host, without this stub nothing fires.
    stub(NervesTime, :synchronized?, fn -> true end)
    :ok
  end

  describe "due_occurrence/3" do
    test "is never due when the feature is disabled" do
      now = ~N[2026-07-30 03:00:00]

      assert :not_due = AutoReboot.due_occurrence(%{interval: nil, reboot_at: now}, now, 120)
      assert :not_due = AutoReboot.due_occurrence(%{interval: 24, reboot_at: nil}, now, 120)
    end

    test "is due within the tolerance window of an occurrence" do
      config = %{interval: 24, reboot_at: ~N[2026-07-30 03:00:00]}

      assert {:ok, ~N[2026-07-30 03:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-07-30 03:00:00], 120)

      assert {:ok, ~N[2026-07-30 03:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-07-30 03:01:59], 120)

      assert :not_due = AutoReboot.due_occurrence(config, ~N[2026-07-30 03:02:00], 120)
    end

    test "is due on every occurrence of the series, not only on the anchor" do
      config = %{interval: 6, reboot_at: ~N[2026-07-30 03:00:00]}

      assert {:ok, ~N[2026-07-30 09:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-07-30 09:00:30], 120)

      assert {:ok, ~N[2026-07-30 21:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-07-30 21:00:30], 120)

      assert :not_due = AutoReboot.due_occurrence(config, ~N[2026-07-30 12:00:00], 120)
    end

    test "is never due before the anchor" do
      config = %{interval: 24, reboot_at: ~N[2026-08-01 03:00:00]}

      # Same time of day, two days early: the series doesn't extend backwards.
      assert :not_due = AutoReboot.due_occurrence(config, ~N[2026-07-30 03:00:10], 120)
      assert :not_due = AutoReboot.due_occurrence(config, ~N[2026-08-01 02:59:59], 120)

      assert {:ok, ~N[2026-08-01 03:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-08-01 03:00:00], 120)
    end

    test "is not due when the clock is still unset" do
      config = %{interval: 24, reboot_at: ~N[2026-07-30 03:00:00]}

      assert :not_due = AutoReboot.due_occurrence(config, ~N[1970-01-01 03:00:00], 120)
    end

    test "keeps the local time of day across DST transitions" do
      config = %{interval: 24, reboot_at: ~N[2025-01-01 03:00:00]}

      # 575 days and 3 DST transitions later, still aligned on 03:00 local.
      assert {:ok, ~N[2026-07-30 03:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-07-30 03:00:20], 120)
    end

    test "is due across a DST spring forward gap" do
      # Europe/London loses an hour on 2026-03-29, so 21:00 -> 03:00 is 6
      # wall clock hours but only 5 real ones.
      config = %{interval: 6, reboot_at: ~N[2026-03-28 21:00:00]}

      assert {:ok, ~N[2026-03-29 03:00:00]} =
               AutoReboot.due_occurrence(config, ~N[2026-03-29 03:00:00], 120)
    end
  end

  describe "the worker" do
    test "reboots once and only once when an occurrence is due" do
      set_config(%{interval: 24, reboot_at: naive_now()})
      expect(DiskMounter, :umount, 1, fn -> :ok end)

      logs =
        capture_log(fn ->
          start_worker()
          Process.sleep(400)
        end)

      assert logs =~ "[AutoReboot] rebooting the device"
      assert [event] = reboot_events()
      assert event.metadata["reason"] == "auto_reboot"
      assert event.metadata["interval"] == 24
      assert event.metadata["timezone"] == "UTC"
    end

    test "does not reboot when the feature is disabled" do
      reject(&DiskMounter.umount/0)

      start_worker()
      Process.sleep(200)

      assert reboot_events() == []
    end

    test "does not reboot outside the tolerance window" do
      reject(&DiskMounter.umount/0)
      set_config(%{interval: 24, reboot_at: naive_now(-600)})

      start_worker()
      Process.sleep(200)

      assert reboot_events() == []
    end

    test "does not reboot before the anchor" do
      reject(&DiskMounter.umount/0)
      set_config(%{interval: 24, reboot_at: naive_now(2 * 24 * 60 * 60)})

      start_worker()
      Process.sleep(200)

      assert reboot_events() == []
    end

    test "does not reboot when NTP is not synced" do
      reject(&DiskMounter.umount/0)
      stub(NervesTime, :synchronized?, fn -> false end)
      set_config(%{interval: 24, reboot_at: naive_now()})

      logs =
        capture_log(fn ->
          start_worker()
          Process.sleep(200)
        end)

      assert logs =~ "NTP not synced"
      assert reboot_events() == []
    end

    test "does not reboot before the grace period elapsed" do
      reject(&DiskMounter.umount/0)
      set_config(%{interval: 24, reboot_at: naive_now()})

      # A long grace with a manual tick isolates the uptime guard from the timer.
      pid = start_worker(grace: to_timeout(hour: 1))

      logs =
        capture_log(fn ->
          send(pid, :check_reboot)
          Process.sleep(100)
        end)

      assert logs =~ "below the grace period"
      assert reboot_events() == []
    end

    test "does not reboot twice within half an interval" do
      reject(&DiskMounter.umount/0)
      set_config(%{interval: 24, reboot_at: naive_now()})
      {:ok, _event} = Events.create_event(%{type: "reboot", time: DateTime.utc_now()})

      logs =
        capture_log(fn ->
          start_worker()
          Process.sleep(200)
        end)

      assert logs =~ "already rebooted"
      assert length(reboot_events()) == 1
    end

    test "reboots again once half an interval elapsed" do
      set_config(%{interval: 24, reboot_at: naive_now()})
      expect(DiskMounter, :umount, 1, fn -> :ok end)

      {:ok, _event} =
        Events.create_event(%{type: "reboot", time: DateTime.add(DateTime.utc_now(), -13, :hour)})

      start_worker()
      Process.sleep(400)

      assert length(reboot_events()) == 2
    end

    test "interprets the anchor in the configured timezone" do
      timezone = "Australia/Sydney"
      expect(DiskMounter, :umount, 1, fn -> :ok end)

      reboot_at =
        timezone |> DateTime.now!() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)

      set_config(%{interval: 24, reboot_at: reboot_at, timezone: timezone})

      start_worker()
      Process.sleep(400)

      assert [_event] = reboot_events()
    end

    test "does not reboot when the anchor belongs to another timezone" do
      reject(&DiskMounter.umount/0)

      reboot_at =
        "Australia/Sydney"
        |> DateTime.now!()
        |> DateTime.to_naive()
        |> NaiveDateTime.truncate(:second)

      set_config(%{interval: 24, reboot_at: reboot_at, timezone: "UTC"})

      start_worker()
      Process.sleep(200)

      assert reboot_events() == []
    end

    test "survives a timezone that's no longer known" do
      reject(&DiskMounter.umount/0)
      set_config(%{interval: 24, reboot_at: naive_now()})
      # A long grace keeps the timer from firing before the state is patched.
      pid = start_worker(grace: to_timeout(hour: 1))

      # Bypass the changeset validation, the value may predate it.
      :sys.replace_state(pid, fn state ->
        %{state | config: %{state.config | timezone: "Mars/Olympus"}}
      end)

      logs =
        capture_log(fn ->
          send(pid, :check_reboot)
          Process.sleep(100)
        end)

      assert logs =~ "invalid timezone"
      assert Process.alive?(pid)
      assert reboot_events() == []
    end

    test "picks up a settings update" do
      expect(DiskMounter, :umount, 1, fn -> :ok end)
      start_worker()
      Process.sleep(100)

      assert reboot_events() == []

      set_config(%{interval: 24, reboot_at: naive_now()})
      Process.sleep(400)

      assert [_event] = reboot_events()
    end

    test "reboots the device on a nerves target" do
      Mimic.copy(Nerves.Runtime)
      # Registered before the worker starts: the real reboot/0 halts the VM.
      expect(Nerves.Runtime, :reboot, fn -> :ok end)
      expect(DiskMounter, :umount, 1, fn -> :ok end)

      on_exit(fn -> Application.put_env(:ex_nvr_fw, :target, :host) end)
      Application.put_env(:ex_nvr_fw, :target, :ex_nvr_rpi5)

      set_config(%{interval: 24, reboot_at: naive_now()})

      start_worker()
      Process.sleep(400)

      assert [_event] = reboot_events()
    end
  end

  defp start_worker(opts \\ []) do
    start_link_supervised!({AutoReboot, Keyword.merge(@opts, opts)})
  end

  defp set_config(params) do
    {:ok, _settings} = SystemSettings.update_auto_reboot_settings(params)
  end

  defp naive_now(shift \\ 0) do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.add(shift)
  end

  defp reboot_events do
    Repo.all(from(e in ExNVR.Events.Event, where: e.type == "reboot", order_by: e.time))
  end
end
