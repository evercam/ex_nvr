defmodule ExNVR.Activity.Writer do
  @moduledoc """
  Buffers activity entries and writes them to the database in batches.

  SQLite allows a single writer at a time, batching keeps the callers (pipelines,
  monitors, LiveViews) from ever waiting on activity log inserts.

  Entries are flushed every `:flush_interval` ms, as soon as `:max_batch` entries
  are buffered, on `flush/1` and when the process terminates. If the database
  is unavailable, entries are kept and retried, up to `:max_buffer` entries after
  which the oldest are dropped.
  """

  use GenServer

  require Logger

  alias ExNVR.Activity
  alias ExNVR.Activity.Entry

  @default_flush_interval :timer.seconds(1)
  @default_max_batch 50
  @default_max_buffer 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Buffers an entry, returns immediately.
  """
  @spec write(GenServer.server(), Entry.t()) :: :ok
  def write(server \\ __MODULE__, %Entry{} = entry), do: GenServer.cast(server, {:write, entry})

  @doc """
  Buffers an entry and flushes the buffer, returns once the entry is persisted.
  """
  @spec write_sync(GenServer.server(), Entry.t(), timeout()) :: :ok | {:error, term()}
  def write_sync(server \\ __MODULE__, %Entry{} = entry, timeout \\ 5_000) do
    GenServer.call(server, {:write_sync, entry}, timeout)
  end

  @spec flush(GenServer.server(), timeout()) :: :ok | {:error, term()}
  def flush(server \\ __MODULE__, timeout \\ 5_000), do: GenServer.call(server, :flush, timeout)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     %{
       buffer: [],
       size: 0,
       timer: nil,
       flush_interval: Keyword.get(opts, :flush_interval, @default_flush_interval),
       max_batch: Keyword.get(opts, :max_batch, @default_max_batch),
       max_buffer: Keyword.get(opts, :max_buffer, @default_max_buffer)
     }}
  end

  @impl true
  def handle_cast({:write, entry}, state) do
    state = buffer(state, entry)

    if state.size >= state.max_batch do
      {:noreply, elem(do_flush(state), 1)}
    else
      {:noreply, schedule_flush(state)}
    end
  end

  @impl true
  def handle_call({:write_sync, entry}, _from, state) do
    {result, state} = state |> buffer(entry) |> do_flush()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    {result, state} = do_flush(state)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:flush, state) do
    {_result, state} = do_flush(%{state | timer: nil})
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    do_flush(state)
    :ok
  end

  defp buffer(%{size: size, max_buffer: max} = state, entry) when size >= max do
    Logger.warning("[Activity] buffer full, dropping oldest entry")
    %{state | buffer: [entry | Enum.drop(state.buffer, -1)]}
  end

  defp buffer(state, entry), do: %{state | buffer: [entry | state.buffer], size: state.size + 1}

  defp do_flush(%{size: 0} = state), do: {:ok, cancel_timer(state)}

  defp do_flush(state) do
    state = cancel_timer(state)

    case Activity.insert_entries(Enum.reverse(state.buffer)) do
      :ok ->
        {:ok, %{state | buffer: [], size: 0}}

      {:error, reason} = error ->
        Logger.error("[Activity] failed to write #{state.size} entries: #{inspect(reason)}")
        {error, schedule_flush(state)}
    end
  end

  defp schedule_flush(%{timer: nil} = state) do
    %{state | timer: Process.send_after(self(), :flush, state.flush_interval)}
  end

  defp schedule_flush(state), do: state

  defp cancel_timer(%{timer: nil} = state), do: state

  defp cancel_timer(state) do
    Process.cancel_timer(state.timer)
    %{state | timer: nil}
  end
end
