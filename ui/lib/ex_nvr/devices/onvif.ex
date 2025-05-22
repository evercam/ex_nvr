defmodule ExNVR.Devices.Onvif do
  @moduledoc false

  require Logger

  alias __MODULE__.AutoConfig
  alias ExNVR.Model.Device
  alias Onvif.Devices.SystemDateAndTime
  alias Onvif.Media2.Profile.VideoEncoder
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

  @spec all_config(Device.t()) :: map()
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

  # Auto configure cameras
  @spec auto_configure(Onvif.Device.t()) :: AutoConfig.t()
  def auto_configure(%{manufacturer: vendor} = onvif_device)
      when vendor in ["HIKVISION", "Milesight Technology Co.,Ltd."] do
    %AutoConfig{}
    |> do_configure_profiles(onvif_device)
  end

  def auto_configure(_onvif_device), do: %AutoConfig{}

  defp do_configure_profiles(auto_config, onvif_device) do
    case Onvif.Media2.get_profiles(onvif_device) do
      {:ok, profiles} ->
        auto_config
        |> do_configure_profile(onvif_device, Enum.at(profiles, 0), :main_stream)
        |> do_configure_profile(onvif_device, Enum.at(profiles, 1), :sub_stream)

      _error ->
        auto_config
    end
  end

  defp do_configure_profile(auto_config, _onvif_device, nil, _profile_type), do: auto_config

  defp do_configure_profile(auto_config, onvif_device, profile, profile_type) do
    config_options_result =
      Onvif.Media2.get_video_encoder_configuration_options(onvif_device,
        profile_token: profile.reference_token
      )

    with {:ok, configs} <- config_options_result,
         :ok <- set_video_encoder_config(onvif_device, profile, configs, profile_type) do
      Map.put(auto_config, profile_type, true)
    else
      {:error, reason} ->
        Logger.error("[Onvif] could not configure profile: #{inspect(reason)}")
        auto_config
    end
  end

  defp set_video_encoder_config(onvif_device, profile, configs, profile_type) do
    {codec, bit_rate, gov_length_coeff} =
      case profile_type do
        :main_stream -> {:h265, 3072, 4}
        :sub_stream -> {:h264, 572, 2}
      end

    config =
      Enum.find(configs, &(&1.encoding == codec)) ||
        Enum.find(configs, &(&1.encoding == :h264))

    frame_rate = select_frame_rate(config.frame_rates_supported)

    video_encoder = %VideoEncoder{
      profile.video_encoder_configuration
      | encoding: config.encoding,
        gov_length: trunc(frame_rate * gov_length_coeff),
        quality: Float.ceil((config.quality_range.max + config.quality_range.min) / 2),
        rate_control: %VideoEncoder.RateControl{
          bitrate_limit: bit_rate,
          constant_bitrate: false,
          frame_rate_limit: frame_rate
        },
        resolution: select_resolution(config.resolutions_available)
    }

    Onvif.Media2.set_video_encoder_configuration(onvif_device, video_encoder)
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

  defp select_frame_rate(frame_rates) do
    frame_rates
    |> Enum.sort()
    |> Enum.drop_while(&(&1 < 8))
    |> hd()
  end

  defp select_resolution(resolutions) do
    resolutions
    |> Enum.sort_by(& &1.height, :desc)
    |> hd()
  end
end
