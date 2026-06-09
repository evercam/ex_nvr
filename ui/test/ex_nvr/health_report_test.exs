defmodule ExNVR.HealthReportTest do
  @moduledoc false
  # async: false because the checks/0 tests mutate Application env globally.
  use ExUnit.Case, async: false

  alias ExNVR.HealthReport

  describe ":devices_recording" do
    @check %{name: :cameras, label: "Cameras recording", kind: :devices_recording}

    test "fails when no cameras are configured" do
      assert [%{name: :cameras, status: :failing, detail: detail}] =
               HealthReport.report(checks: [@check], devices: [])

      assert detail == "No cameras configured"
    end

    test "ok when every device is recording" do
      devices = [%{name: "Front", state: :recording}, %{name: "Back", state: :recording}]

      assert [%{status: :ok, detail: "2 cameras recording"}] =
               HealthReport.report(checks: [@check], devices: devices)
    end

    test "ok with a single recording device uses singular noun" do
      assert [%{status: :ok, detail: "1 camera recording"}] =
               HealthReport.report(
                 checks: [@check],
                 devices: [%{name: "Front", state: :recording}]
               )
    end

    test "fails when a device is not recording, listing the offenders" do
      devices = [
        %{name: "Front", state: :recording},
        %{name: "Back", state: :stopped},
        %{name: "Side", state: :failed}
      ]

      assert [%{status: :failing, detail: detail}] =
               HealthReport.report(checks: [@check], devices: devices)

      assert detail == "2 not recording: Back, Side"
    end
  end

  describe ":state_field_present" do
    @check %{
      name: :battery,
      label: "Battery monitor reachable",
      kind: :state_field_present,
      field: :battery_monitor
    }

    test "ok when field is non-nil" do
      assert [%{status: :ok}] =
               HealthReport.report(
                 checks: [@check],
                 state: %{battery_monitor: %{v: 25_000}}
               )
    end

    test "insufficient_data when field is missing or nil" do
      for state <- [%{}, %{battery_monitor: nil}] do
        assert [%{status: :insufficient_data, detail: "No data for battery_monitor"}] =
                 HealthReport.report(checks: [@check], state: state)
      end
    end
  end

  describe ":state_field with a path" do
    @check %{
      name: :netbird,
      label: "Netbird connected",
      kind: :state_field,
      field: :netbird,
      path: ["daemonStatus"],
      expected: "Connected"
    }

    test "ok when nested value matches" do
      assert [%{status: :ok}] =
               HealthReport.report(
                 checks: [@check],
                 state: %{netbird: %{"daemonStatus" => "Connected"}}
               )
    end

    test "fails when nested value differs" do
      assert [%{status: :failing, detail: detail}] =
               HealthReport.report(
                 checks: [@check],
                 state: %{netbird: %{"daemonStatus" => "Disconnected"}}
               )

      assert detail =~ "netbird.daemonStatus"
      assert detail =~ "Disconnected"
    end

    test "insufficient_data when the field or sub-path is missing" do
      for state <- [%{}, %{netbird: nil}, %{netbird: %{}}] do
        assert [%{status: :insufficient_data}] =
                 HealthReport.report(checks: [@check], state: state)
      end
    end
  end

  describe ":state_field with expected as a list" do
    @check %{
      name: :status,
      label: "Status",
      kind: :state_field,
      field: :status,
      expected: [:active, :recording]
    }

    test "ok when value is in the expected list" do
      assert [%{status: :ok}] =
               HealthReport.report(checks: [@check], state: %{status: :recording})
    end

    test "fails when value is outside the expected list" do
      assert [%{status: :failing}] =
               HealthReport.report(checks: [@check], state: %{status: :stopped})
    end
  end

  describe ":mobius_range" do
    @check %{
      name: :cpu,
      label: "CPU under 90% for 10 min",
      kind: :mobius_range,
      metric: "ex_nvr.system.cpu.usage",
      range: 0..90,
      window: {10, :minute}
    }

    test "ok when every sample sits inside the range" do
      assert [%{status: :ok, detail: detail}] =
               HealthReport.report(
                 checks: [@check],
                 series_fn: stub_series([10, 20, 30, 80])
               )

      assert detail == "4 samples in 0..90"
    end

    test "fails on the first sample outside the range" do
      assert [%{status: :failing, detail: detail}] =
               HealthReport.report(
                 checks: [@check],
                 series_fn: stub_series([10, 95, 60])
               )

      assert detail =~ "ex_nvr.system.cpu.usage = 95"
      assert detail =~ "0..90"
    end

    test "insufficient_data when there are no samples in the window" do
      assert [%{status: :insufficient_data, detail: detail}] =
               HealthReport.report(checks: [@check], series_fn: stub_series([]))

      assert detail =~ "ex_nvr.system.cpu.usage"
    end

    test "passes tags through and uses the configured window" do
      caller = self()

      series_fn = fn metric, tags, window ->
        send(caller, {:series_call, metric, tags, window})
        []
      end

      tagged = Map.put(@check, :tags, %{device_id: "abc"})

      HealthReport.report(checks: [tagged], series_fn: series_fn)

      assert_received {:series_call, "ex_nvr.system.cpu.usage", %{device_id: "abc"},
                       {10, :minute}}
    end
  end

  describe "overall/1" do
    test ":ok when every check is :ok" do
      assert :ok = HealthReport.overall([result(:ok), result(:ok)])
    end

    test ":failing wins over :insufficient_data" do
      assert :failing =
               HealthReport.overall([result(:ok), result(:failing), result(:insufficient_data)])
    end

    test ":insufficient_data when no failures but some unknown" do
      assert :insufficient_data =
               HealthReport.overall([result(:ok), result(:insufficient_data)])
    end

    test ":ok on an empty list" do
      assert :ok = HealthReport.overall([])
    end
  end

  describe "checks/0" do
    test "reflects what's configured under :ex_nvr, :health_checks" do
      previous = Application.get_env(:ex_nvr, :health_checks)

      try do
        Application.delete_env(:ex_nvr, :health_checks)
        assert HealthReport.checks() == []

        Application.put_env(:ex_nvr, :health_checks, [
          %{name: :only, label: "Only", kind: :state_field_present, field: :ups}
        ])

        assert [%{name: :only}] = HealthReport.checks()
      after
        if previous,
          do: Application.put_env(:ex_nvr, :health_checks, previous),
          else: Application.delete_env(:ex_nvr, :health_checks)
      end
    end

    test "report/0 returns [] when no checks are configured" do
      previous = Application.get_env(:ex_nvr, :health_checks)

      try do
        Application.delete_env(:ex_nvr, :health_checks)
        assert HealthReport.report() == []
      after
        if previous,
          do: Application.put_env(:ex_nvr, :health_checks, previous),
          else: Application.delete_env(:ex_nvr, :health_checks)
      end
    end
  end

  defp stub_series(samples), do: fn _metric, _tags, _window -> samples end

  defp result(status),
    do: %{name: :test, label: "test", status: status, detail: nil}
end
