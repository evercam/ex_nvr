defmodule ExNVR.Nerves.Giraffe.RTC.NervesTime do
  @moduledoc false

  @behaviour NervesTime.RealTimeClock

  require Logger

  alias ExNVR.Nerves.Giraffe.RTC

  @default_bus_name "i2c-1"

  @impl NervesTime.RealTimeClock
  def init(args) do
    args |> Keyword.get(:bus_name, @default_bus_name) |> RTC.open()
  end

  @impl NervesTime.RealTimeClock
  def terminate(bus), do: RTC.close(bus)

  @impl NervesTime.RealTimeClock
  def get_time(bus) do
    with {:ok, true} <- RTC.oscillator_running?(bus),
         {:ok, %NaiveDateTime{} = time} <- RTC.get_time(bus) do
      {:ok, time, bus}
    else
      {:ok, false} ->
        Logger.warning("[RTC] oscillator not running, time is unset")
        {:unset, bus}

      {:error, reason} ->
        Logger.error("[RTC] failed to read time: #{inspect(reason)}")
        {:unset, bus}
    end
  end

  @impl NervesTime.RealTimeClock
  def set_time(bus, %NaiveDateTime{} = time) do
    case RTC.set_time(bus, time) do
      :ok -> :ok
      {:error, reason} -> Logger.error("[Giraffe.RTC] failed to set time: #{inspect(reason)}")
    end

    bus
  end
end
