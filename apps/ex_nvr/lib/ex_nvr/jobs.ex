defmodule ExNVR.Jobs do
  @moduledoc """
  The Jobs that run periodically context.
  """

  use GenServer

  alias ExNVR.Accounts.UserToken
  alias ExNVR.Repo

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    # Schedule work to be performed
    schedule_job()
    {:ok, state}
  end

  def handle_info(:delete_expired_tokens, state) do
    # handle deleting expired tokens
    delete_all_expired_tokens()
    # Reschedule once more
    schedule_job()
    {:noreply, state}
  end

  defp schedule_job() do
    # In 2 hours
    Process.send_after(self(), :delete_expired_tokens, 2 * 60 * 60 * 1000)
  end

  def delete_all_expired_tokens() do
    UserToken.get_expired_tokens()
    |> Repo.delete_all()
  end
end
