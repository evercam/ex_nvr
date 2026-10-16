defmodule ExNVR.Activity.Pruner do
  @moduledoc """
  Deletes activity entries older than the configured retention.

  Opt-in: only started when `:activity_retention_days` is configured
  (`EXNVR_ACTIVITY_RETENTION_DAYS`), entries are kept forever otherwise.
  """

  use GenServer

  require Logger

  alias ExNVR.Activity

  @interval :timer.hours(24)
  @initial_delay :timer.minutes(1)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    retention_days = Keyword.fetch!(opts, :retention_days)
    Process.send_after(self(), :prune, Keyword.get(opts, :initial_delay, @initial_delay))
    {:ok, %{retention_days: retention_days, interval: Keyword.get(opts, :interval, @interval)}}
  end

  @impl true
  def handle_info(:prune, state) do
    count = Activity.delete_older_than(state.retention_days)

    if count > 0 do
      Logger.info("[Activity] deleted #{count} entries older than #{state.retention_days} days")
    end

    Process.send_after(self(), :prune, state.interval)
    {:noreply, state}
  end
end
