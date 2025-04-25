defmodule ExNVR.Sentry do
  @moduledoc false

  def before_send(%{message: %{formatted: message}} = event) do
    contents = [
      "Error while connecting to main_stream",
      "Error while connecting to sub_stream"
    ]

    if String.contains?(message || "", contents), do: nil, else: event
  end

  def before_send(event), do: event
end
