defmodule ExNVR.Nerves.Giraffe.FanController do
  @moduledoc """
  Drive the EMC2101 fan controller.
  """

  use GenServer

  require Logger

  alias ExNVR.Nerves.Giraffe.Fan

  @sync_interval to_timeout(second: 30)

  def start_link(options) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @spec temperatures() ::
          {:ok, %{internal: number(), external: number()}} | {:error, term()}
  def temperatures do
    GenServer.call(__MODULE__, :temperatures)
  end

  @spec speed() :: {:ok, non_neg_integer()} | {:error, term()}
  def speed do
    GenServer.call(__MODULE__, :speed)
  end

  @spec set_speed(0..100) :: :ok | {:error, term()}
  def set_speed(percentage) when percentage in 0..100 do
    GenServer.call(__MODULE__, {:set_speed, percentage})
  end

  @spec set_lookup_table(Fan.lookup_table()) :: :ok | {:error, term()}
  def set_lookup_table(table \\ Fan.default_lookup_table())
      when length(table) in 1..8 do
    GenServer.call(__MODULE__, {:set_lookup_table, table})
  end

  @impl true
  def init(options) do
    bus_name = Keyword.get(options, :bus_name, "i2c-1")

    case Fan.open(bus_name) do
      {:ok, bus} ->
        {:ok, %{bus: bus, external_sensor?: true}, {:continue, :setup}}

      {:error, reason} ->
        Logger.error("[FanController] failed to open #{bus_name}: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:setup, state) do
    with :ok <- Fan.enable_tachometer(state.bus),
         :ok <- Fan.set_lookup_table(state.bus, Fan.default_lookup_table()) do
      :ok
    else
      {:error, reason} -> Logger.error("[FanController] setup failed: #{inspect(reason)}")
    end

    {:noreply, state, {:continue, :detect_sensor}}
  end

  @impl true
  def handle_continue(:detect_sensor, state) do
    case Fan.external_sensor?(state.bus) do
      {:ok, true} ->
        {:noreply, state}

      {:ok, false} ->
        Logger.info("[FanController] no external sensor, forcing internal temperature")
        {:noreply, %{state | external_sensor?: false}, {:continue, :sync_forced_temp}}

      {:error, reason} ->
        Logger.error("[FanController] failed to detect external sensor: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_continue(:sync_forced_temp, state) do
    with {:ok, temp} <- Fan.internal_temperature(state.bus),
         :ok <- Fan.set_forced_external_temp(state.bus, temp) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("[FanController] failed to sync forced temperature: #{inspect(reason)}")
    end

    Process.send_after(self(), :sync_forced_temp, @sync_interval)
    {:noreply, state}
  end

  @impl true
  def handle_info(:sync_forced_temp, state) do
    handle_continue(:sync_forced_temp, state)
  end

  @impl true
  def handle_call(:temperatures, _from, state) do
    {:reply, Fan.temperatures(state.bus), state}
  end

  @impl true
  def handle_call(:speed, _from, state) do
    {:reply, Fan.speed(state.bus), state}
  end

  @impl true
  def handle_call({:set_speed, percentage}, _from, state) do
    {:reply, Fan.set_speed(state.bus, percentage), state}
  end

  @impl true
  def handle_call({:set_lookup_table, table}, _from, state) do
    {:reply, Fan.set_lookup_table(state.bus, table), state}
  end
end
