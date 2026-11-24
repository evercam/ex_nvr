defmodule ExNVR.Nerves.ErrorReporting.SentryEnricher do
  @moduledoc """
  A Sentry `:before_send` callback that tags every event from a device with
  its NervesHub identity.

    * `release` is set from the running firmware's version, rather than the
      version written into the Sentry config when the firmware was built.
    * `nerves_hub.device`, `firmware_uuid` and `kit_id` tags make events
      searchable by device and by exact firmware build.
    * `nerves_hub_errors` links to the device's Errors tab in NervesHub, which
      also has the crashes Sentry missed while the device was offline.
  """

  alias ExNVR.Nerves.ErrorReporting

  @spec before_send(Sentry.Event.t()) :: Sentry.Event.t()
  def before_send(%Sentry.Event{} = event) do
    device = ErrorReporting.device()

    tags =
      %{
        "nerves_hub.device" => device.serial,
        "firmware_uuid" => device.firmware_uuid,
        "kit_id" => device.kit_id
      }
      |> ErrorReporting.reject_nil_values()

    extra =
      %{"nerves_hub_errors" => ErrorReporting.nerves_hub_errors_url()}
      |> ErrorReporting.reject_nil_values()

    %{
      event
      | release: release(device.firmware_version, event.release),
        tags: Map.merge(event.tags || %{}, tags),
        extra: Map.merge(event.extra || %{}, extra)
    }
  rescue
    # Tagging is a nicety. An event without the tags is better than no event.
    _error -> event
  end

  defp release(version, _configured) when is_binary(version), do: "ex_nvr@" <> version
  defp release(_missing, configured), do: configured
end
