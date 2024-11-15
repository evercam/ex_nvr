defmodule ExNVRWeb.HlsStreamingMonitor do
  @moduledoc """
  Monitors current HLS streaming pipelines

  If an HLS streaming pipeline is not accessed by a client for 1 minute, we
  stop creating HLS playlists
  """

  use GenServer

  require Logger

  @cleanup_interval :timer.seconds(3)
  @stale_time 45

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def register(id, cleanup_fn) do
    Logger.info("Register new HLS stream: #{id}")
    :ets.insert(__MODULE__, {id, cleanup_fn, current_time_s()})
  end

  def update_last_access_time(id) do
    :ets.update_element(__MODULE__, id, {3, current_time_s()})
  end

  @impl true
  def init(nil) do
    :ets.new(__MODULE__, [:named_table, :public, :set])
    Process.send_after(self(), :tick, @cleanup_interval)
    {:ok, nil}
  end

  @impl true
  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, @cleanup_interval)
    maybe_clean_up()
    {:noreply, state}
  end

  @impl true
  def handle_info(_, state) do
    {:noreply, state}
  end

  defp current_time_s() do
    DateTime.utc_now() |> DateTime.to_unix()
  end

  defp maybe_clean_up() do
    :ets.tab2list(__MODULE__)
    |> Enum.filter(fn {_, _, last_access_time} ->
      current_time_s() - last_access_time >= @stale_time
    end)
    |> Enum.each(fn {key, clean_up_fn, _} ->
      Logger.info(
        "HLS stream not used for more than #{@stale_time} seconds, stop streaming and clean up"
      )

      # don't crash the process if there's a problem
      # in clean up function
      Task.start(clean_up_fn || fn -> :ok end)
      :ets.delete(__MODULE__, key)
    end)
  end
end
