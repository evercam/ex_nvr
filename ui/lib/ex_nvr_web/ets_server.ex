defmodule ExNVRWeb.ETSServer do
  use GenServer

  @table :export_table

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def insert_to_ets(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def reset_table() do
    GenServer.call(__MODULE__, :reset)
  end

  @impl true
  def init(_) do
    create_table()
    {:ok, %{}}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    :ets.insert(@table, {key, value})
    {:reply, :ok, state}
  end

  def handle_call({:get, key}, _from, state) do
    result =
      case :ets.lookup(@table, key) do
        [{^key, value}] -> {key, value}
        [] -> :not_found
      end

    {:reply, result, state}
  end

  def handle_call(:reset, _from, state) do
    create_table()
    {:reply, :ok, state}
  end

  defp create_table() do
    :ets.new(@table, [:set, :public, :named_table])
  end
end
