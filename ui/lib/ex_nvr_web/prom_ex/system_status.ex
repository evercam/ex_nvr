defmodule ExNVRWeb.PromEx.SystemStatus do
  @moduledoc """
  A module responsible for exposing metrics and stats about the
  whole system.
  """

  use PromEx.Plugin

  alias ExNVR.SystemStatus
  alias PromEx.MetricTypes.Polling

  @impl true
  def polling_metrics(opts) do
    poll_rate = Keyword.get(opts, :poll_rate, 15_000)

    [
      solar_charger_metrics(poll_rate)
    ]
  end

  defp solar_charger_metrics(poll_rate) do
    Polling.build(
      :solar_charger_polling_events,
      poll_rate,
      {__MODULE__, :solar_charger, []},
      [
        last_value(
          "ex_nvr.solar_charger.info",
          event_name: "ex_nvr.solar_charger.info",
          description: "The solar charger controller infomation",
          measurement: :value,
          tags: [:vendor, :product_id, :firmware, :serial_number]
        ),
        last_value(
          "ex_nvr.solar_charger.voltage",
          event_name: "ex_nvr.solar_charger.voltage",
          description: "The controller main channel (or battery) voltage in mV",
          measurement: :value,
          tags: [:product_id, :serial_number]
        ),
        last_value(
          "ex_nvr.solar_charger.current",
          event_name: "ex_nvr.solar_charger.current",
          description: "The controller main channel (or battery) current in mA",
          measurement: :value,
          tags: [:product_id, :serial_number]
        ),
        last_value(
          "ex_nvr.solar_charger.panel_voltage",
          event_name: "ex_nvr.solar_charger.panel_voltage",
          description: "The solar panel voltage in mV",
          measurement: :value,
          tags: [:product_id, :serial_number]
        ),
        last_value(
          "ex_nvr.solar_charger.panel_power",
          event_name: "ex_nvr.solar_charger.panel_power",
          description: "The solar panel power in W",
          measurement: :value,
          tags: [:product_id, :serial_number]
        )
      ]
    )
  end

  def solar_charger() do
    if solar_charger = SystemStatus.get(:solar_charger) do
      execute_solar_charger_info_event(solar_charger)
      execute_solar_charger_voltage_event(solar_charger)
      execute_solar_charger_current_event(solar_charger)
      execute_solar_charger_panel_voltage_event(solar_charger)
      execute_solar_charger_panel_power_event(solar_charger)
    end
  end

  defp execute_solar_charger_info_event(data) do
    :telemetry.execute(
      [:ex_nvr, :solar_charger, :info],
      %{value: 1},
      %{
        vendor: "Victron",
        product_id: data.pid,
        firmware: data.fw,
        serial_number: data.serial_number
      }
    )
  end

  defp execute_solar_charger_voltage_event(%{v: nil}), do: :ok

  defp execute_solar_charger_voltage_event(data) do
    :telemetry.execute(
      [:ex_nvr, :solar_charger, :voltage],
      %{value: data.v},
      %{
        product_id: data.pid,
        serial_number: data.serial_number
      }
    )
  end

  defp execute_solar_charger_current_event(%{i: nil}), do: :ok

  defp execute_solar_charger_current_event(data) do
    :telemetry.execute(
      [:ex_nvr, :solar_charger, :current],
      %{value: data.i},
      %{
        product_id: data.pid,
        serial_number: data.serial_number
      }
    )
  end

  defp execute_solar_charger_panel_voltage_event(%{vpv: nil}), do: :ok

  defp execute_solar_charger_panel_voltage_event(data) do
    :telemetry.execute(
      [:ex_nvr, :solar_charger, :panel_voltage],
      %{value: data.vpv},
      %{
        product_id: data.pid,
        serial_number: data.serial_number
      }
    )
  end

  defp execute_solar_charger_panel_power_event(%{ppv: nil}), do: :ok

  defp execute_solar_charger_panel_power_event(data) do
    :telemetry.execute(
      [:ex_nvr, :solar_charger, :panel_power],
      %{value: data.ppv},
      %{
        product_id: data.pid,
        serial_number: data.serial_number
      }
    )
  end
end
