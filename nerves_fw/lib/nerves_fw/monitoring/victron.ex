defmodule ExNVR.Nerves.Monitoring.Victron do
  @moduledoc """
  Enable/disable Victron energy device monitoring based on the configured power type.
  """

  use Task, restart: :transient

  alias ExNVR.Hardware.SerialPortChecker
  alias ExNVR.Nerves.SystemSettings

  def start_link(_opts) do
    Task.start_link(__MODULE__, :run, [])
  end

  @doc false
  def run do
    SystemSettings.get_settings()
    |> Map.fetch!(:power_type)
    |> set()
  end

  @spec set(atom()) :: :ok
  def set(power_type) when power_type in [:solar, :generator], do: SerialPortChecker.enable()
  def set(_power_type), do: SerialPortChecker.disable()
end
