defmodule ExNVR.Nerves.SystemSettings do
  @moduledoc """
  Module describing system settings.

  It's stored as a json file in the system.
  """

  @default_path "/data/settings.json"

  @derive Jason.Encoder
  defstruct power_schedule: nil,
            schedule_timezone: "UTC",
            schedule_action: "poweroff",
            monitor_power: false

  @spec get_settings() :: State.t()
  def get_settings() do
    case File.read(settings_path()) do
      {:ok, data} ->
        Jason.decode!(data)
        |> Map.new(fn {key, value} -> {String.to_atom(key), value} end)
        |> then(&struct!(__MODULE__, &1))

      {:error, _reason} ->
        %__MODULE__{}
    end
  end

  @spec update_setting(atom(), any()) :: :ok
  def update_setting(setting, value) do
    get_settings()
    |> Map.put(setting, value)
    |> then(&File.write!(settings_path(), Jason.encode!(&1)))
  end

  defp settings_path() do
    Application.get_env(:ex_nvr_fw, :system_settings_path, @default_path)
  end
end
