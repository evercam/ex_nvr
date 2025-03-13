defmodule ExNVR.Nerves.Giraffe.Init do
  @moduledoc """
  Init Giraffe board.

  The following actions will be run at startup:
    * Power on HDD (GPIO16)
    * Power on PoE (GPIO26)
  """

  use GenServer, restart: :transient

  alias Circuits.GPIO

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil)
  end

  @impl true
  def init(_options) do
    {:ok, nil, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, state) do
    {:ok, gpio1} = GPIO.open("GPIO16", :output)
    {:ok, gpio2} = GPIO.open("GPIO26", :output)

    GPIO.write(gpio1, 1)
    GPIO.write(gpio2, 1)

    GPIO.close(gpio1)
    GPIO.close(gpio2)

    {:stop, :normal, state}
  end
end
