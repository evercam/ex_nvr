defmodule ExNVR.TokenPruner do
  @moduledoc """
  The Jobs that run periodically context.
  """

  use GenServer

  alias ExNVR.Accounts

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_job()
    {:ok, state}
  end

  def handle_info(:delete_expired_tokens, state) do
    prune_expired_tokens()
    schedule_job()
    {:noreply, state}
  end

  defp schedule_job() do
    Process.send_after(self(), :delete_expired_tokens, :timer.hours(2))
  end

  def prune_expired_tokens() do
    Accounts.delete_all_expired_tokens()
  end
end
