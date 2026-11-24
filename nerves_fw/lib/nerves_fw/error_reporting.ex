defmodule ExNVR.Nerves.ErrorReporting do
  @moduledoc """
  Device details shared by the two places errors are reported from the
  firmware: Sentry and NervesHub.

  Crashes go to both through their own `:logger` handlers. Handled errors go
  through `ExNVR.ErrorReporter`, which reaches NervesHub through
  `ExNVR.Nerves.ErrorReporting.NervesHubReporter`. Sentry events are tagged
  with the NervesHub device and firmware by
  `ExNVR.Nerves.ErrorReporting.SentryEnricher`, so one can be found from the
  other.
  """

  alias Nerves.Runtime.KV

  @typedoc "What identifies this device and its firmware."
  @type device :: %{
          serial: String.t() | nil,
          firmware_uuid: String.t() | nil,
          firmware_version: String.t() | nil,
          kit_id: String.t() | nil
        }

  @doc """
  This device and its running firmware.

  Read once and then kept in `:persistent_term`: none of it changes until the
  next boot, and it is read while reporting a crash, which is the worst time to
  make calls to other processes.
  """
  @spec device() :: device()
  def device do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        device = %{
          serial: Nerves.Runtime.serial_number(),
          firmware_uuid: KV.get_active("nerves_fw_uuid"),
          firmware_version: KV.get_active("nerves_fw_version"),
          kit_id: KV.get("nerves_evercam_id")
        }

        :persistent_term.put(__MODULE__, device)
        device

      device ->
        device
    end
  end

  @doc """
  Details attached to every NervesHub error report, on top of the uptime
  NervesHubLink adds itself.

  NervesHub already knows the device and its firmware, so this only adds what
  ties a report to Evercam's own records.
  """
  @spec nerves_hub_context() :: %{String.t() => String.t()}
  def nerves_hub_context do
    %{"kit_id" => device().kit_id}
    |> reject_nil_values()
  end

  @doc """
  The device's Errors tab in NervesHub, or `nil` when the NervesHub address was
  not set when the firmware was built.
  """
  @spec nerves_hub_errors_url() :: String.t() | nil
  def nerves_hub_errors_url do
    with base when is_binary(base) <-
           Application.get_env(:ex_nvr_fw, :nerves_hub_devices_url),
         serial when is_binary(serial) <- device().serial do
      "#{base}/#{serial}/errors"
    else
      _missing -> nil
    end
  end

  @doc false
  @spec reject_nil_values(map()) :: map()
  def reject_nil_values(map) do
    map |> Enum.reject(fn {_key, value} -> is_nil(value) end) |> Map.new()
  end
end
