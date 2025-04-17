defmodule ExNVR.Devices.Onvif do
  @moduledoc false

  alias ExNVR.Model.Device
  alias Onvif.Search.{FindRecordings, GetRecordingSearchResults}
  alias Onvif.Search.Schemas

  @spec discover(Keyword.t()) :: [Onvif.Discovery.Probe.t()]
  def discover(options) do
    Onvif.Discovery.probe(options)
    |> Enum.uniq()
    |> Enum.map(fn probe ->
      # Ignore link local addresses
      probe.address
      |> Enum.reject(&String.starts_with?(&1, ["http://169.254", "https://169.254"]))
      |> then(&Map.put(probe, :address, &1))
    end)
  end

  @spec onvif_device(Device.t()) :: {:ok, Onvif.Device.t()} | {:error, any()}
  def onvif_device(%Device{type: :ip} = device) do
    case Device.http_url(device) do
      nil ->
        {:error, :no_url}

      url ->
        Onvif.Device.new(url, device.credentials.username, device.credentials.password)
    end
  end

  def onvif_device(_device), do: {:error, :not_camera}

  def stream_profiles(%Device{} = device) do
    case onvif_device(device) do
      {:ok, onvif_device} ->
        config = device.stream_config

        [
          {:main_stream, do_get_onvif_stream_profile(onvif_device, config.profile_token)},
          {:sub_stream, do_get_onvif_stream_profile(onvif_device, config.sub_profile_token)}
        ]
        |> Enum.reject(&is_nil(elem(&1, 1)))
        |> Map.new()

      _error ->
        %{}
    end
  end

  @spec get_recordings(Device.t() | Onvif.Device.t()) :: {:ok, [struct()]} | {:error, any()}
  def get_recordings(%Device{} = device) do
    with {:ok, onvif_device} <- onvif_device(device) do
      do_get_recordings(onvif_device)
    end
  end

  def get_recordings(%Onvif.Device{} = device), do: do_get_recordings(device)

  defp do_get_onvif_stream_profile(_onvif_device, nil), do: nil
  defp do_get_onvif_stream_profile(_onvif_device, ""), do: nil

  defp do_get_onvif_stream_profile(onvif_device, profile_token) do
    case Onvif.Media.Ver20.GetProfiles.request(onvif_device, [profile_token]) do
      {:ok, [profile]} -> profile
      _other -> nil
    end
  end

  defp do_get_recordings(%{recording_ver10_service_path: nil}),
    do: {:error, :no_recording_service}

  defp do_get_recordings(device) do
    with {:ok, token} <-
           FindRecordings.request(device, %Schemas.FindRecordings{keep_alive_time: 120}),
         {:ok, result} <-
           GetRecordingSearchResults.request(device, %Schemas.GetRecordingSearchResults{
             search_token: token
           }) do
      {:ok,
       Enum.map(
         result.recording_information,
         &Map.take(&1, ~w(recording_token earliest_recording latest_recording recording_status)a)
       )}
    end
  end
end
