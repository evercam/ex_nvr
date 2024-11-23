defmodule ExNVR.TokenPruner do
  @moduledoc """
  The Jobs that run periodically context.
  """

  use GenServer

  require Logger

  alias ExNVR.Accounts

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_job()
    {:ok, state}
  end

  def handle_info(:delete_expired_tokens, state) do
    Logger.info("TokenPruner: start deleting expired token..")
    Accounts.delete_all_expired_tokens()
    schedule_job()
    {:noreply, state}
  end

  defp schedule_job() do
    Process.send_after(self(), :delete_expired_tokens, :timer.hours(2))
  end
end
