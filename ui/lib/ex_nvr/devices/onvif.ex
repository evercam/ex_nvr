defmodule ExNVR.Devices.Onvif do
  @moduledoc false

  alias ExNVR.Model.Device
  alias Onvif.Devices.SystemDateAndTime
  alias Onvif.Search
  alias Onvif.Search.{FindRecordings, GetRecordingSearchResults}

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

  def all_config(%Device{type: :ip} = device) do
    case onvif_device(device) do
      {:ok, onvif_device} ->
        %{
          stream_profiles: stream_profiles(onvif_device, device),
          camera_information: %{
            manufacturer: onvif_device.manufacturer,
            model: onvif_device.model,
            serial_number: onvif_device.serial_number,
            firmware_version: onvif_device.firmware_version,
            hardware_id: onvif_device.hardware_id
          },
          local_date_time: SystemDateAndTime.local_time(onvif_device.system_date_time),
          local_recordings: local_recordings(onvif_device)
        }

      _other ->
        %{}
    end
  end

  def all_config(_device), do: %{}

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

  @spec get_recordings(Onvif.Device.t()) :: {:ok, [struct()]} | {:error, any()}
  def get_recordings(onvif_device) do
    do_get_recordings(onvif_device)
  end

  defp stream_profiles(onvif_device, device) do
    config = device.stream_config

    [
      {:main_stream, do_get_onvif_stream_profile(onvif_device, config.profile_token)},
      {:sub_stream, do_get_onvif_stream_profile(onvif_device, config.sub_profile_token)}
    ]
    |> Enum.reject(&is_nil(elem(&1, 1)))
    |> Map.new()
  end

  defp do_get_onvif_stream_profile(_onvif_device, nil), do: nil
  defp do_get_onvif_stream_profile(_onvif_device, ""), do: nil

  defp do_get_onvif_stream_profile(onvif_device, profile_token) do
    case Onvif.Media2.get_profiles(onvif_device, token: profile_token, type: ["VideoEncoder"]) do
      {:ok, [profile]} -> profile
      _other -> nil
    end
  end

  defp do_get_recordings(%{recording_ver10_service_path: nil}),
    do: {:error, :no_recording_service}

  defp do_get_recordings(device) do
    with {:ok, token} <- Search.find_recordings(device, %FindRecordings{keep_alive_time: 120}),
         {:ok, result} <-
           Search.get_recording_search_results(device, %GetRecordingSearchResults{
             search_token: token
           }) do
      {:ok,
       Enum.map(
         result.recording_information,
         &Map.take(&1, ~w(recording_token earliest_recording latest_recording recording_status)a)
       )}
    end
  end

  defp local_recordings(onvif_device) do
    case get_recordings(onvif_device) do
      {:ok, recordings} -> recordings
      _error -> []
    end
  end
end
