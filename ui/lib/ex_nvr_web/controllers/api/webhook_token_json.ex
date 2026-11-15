defmodule ExNVRWeb.API.WebhookTokenJSON do
  @moduledoc false

  @spec show(map()) :: map()
  def show(%{webhook_token: webhook_token}) do
    %{
      token: webhook_token.token,
      inserted_at: DateTime.from_naive!(webhook_token.inserted_at, "Etc/UTC")
    }
  end
end
