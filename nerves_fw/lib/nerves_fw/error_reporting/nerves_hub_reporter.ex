defmodule ExNVR.Nerves.ErrorReporting.NervesHubReporter do
  @moduledoc """
  Sends handled errors reported through `ExNVR.ErrorReporter` to NervesHub.

  NervesHubLink holds the report and sends it with its next batch, so this
  returns at once and an error reported while the device is offline still
  arrives once it reconnects. Nothing is sent unless NervesHub has the Error
  Reports extension enabled for the product.
  """

  @behaviour ExNVR.ErrorReporter

  alias ExNVR.Nerves.ErrorReporting

  @impl true
  def report(exception, stacktrace, opts) do
    context =
      opts
      |> Keyword.get(:extra, %{})
      |> Map.new(fn {key, value} -> {to_string(key), to_context_value(value)} end)
      |> Map.put("report_id", opts[:report_id])
      |> ErrorReporting.reject_nil_values()

    NervesHubLink.report_error(exception, stacktrace, group: opts[:group], context: context)
  end

  # NervesHub stores report context as strings, and does not convert what it
  # is sent.
  defp to_context_value(nil), do: nil
  defp to_context_value(value) when is_binary(value), do: value
  defp to_context_value(value), do: inspect(value)
end
