defmodule ExNVR.Nerves.Giraffe.Init do
  @moduledoc """
  Init Giraffe board.

  The following actions will be run at startup:
    * Power on HDD (GPIO16)
    * Power on PoE (GPIO26)
  """

  use GenServer, restart: :transient

  require Logger

  alias Circuits.GPIO
  alias ExNVR.Nerves.SystemSettings

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(_options) do
    res =
      SystemSettings.update(%{
        ups: %{
          enabled: true,
          ac_pin: "GPIO4",
          battery_pin: "GPIO8",
          ac_pin_default: 1,
          battery_pin_default: 1,
          trigger_after: 0,
          low_battery_action: :power_off,
          ac_failure_action: :nothing
        }
      })

    with {:error, _} <- res do
      Logger.error("[Init] failed to update ups settings")
    end

    {:ok, nil, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, state) do
    :ok = GPIO.write_one("GPIO16", 1)
    :ok = GPIO.write_one("GPIO26", 1)

    {:stop, :normal, state}
  end
end
