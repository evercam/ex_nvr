defmodule ExNVR.Devices.Onvif do
  @moduledoc false

  require Logger

  alias __MODULE__.AutoConfig
  alias ExNVR.Model.Device
  alias ExOnvif.Devices.SystemDateAndTime
  alias ExOnvif.Media2
  alias ExOnvif.Media2.Profile.VideoEncoder
  alias ExOnvif.Search
  alias ExOnvif.Search.{FindRecordings, GetRecordingSearchResults}

  @spec discover(Keyword.t()) :: [ExOnvif.Discovery.Probe.t()]
  def discover(options) do
    ExOnvif.Discovery.probe(options)
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

  @spec onvif_device(Device.t()) :: {:ok, ExOnvif.Device.t()} | {:error, any()}
  def onvif_device(%Device{type: :ip} = device) do
    case Device.http_url(device) do
      nil ->
        {:error, :no_url}

      url ->
        ExOnvif.Device.new(url, device.credentials.username, device.credentials.password)
    end
  end

  def onvif_device(_device), do: {:error, :not_camera}

  @spec get_recordings(Onvif.Device.t()) :: {:ok, [struct()]} | {:error, any()}
  def get_recordings(onvif_device) do
    do_get_recordings(onvif_device)
  end

  # Auto configure cameras
  @spec auto_configure(ExOnvif.Device.t()) :: AutoConfig.t()
  def auto_configure(%{manufacturer: "AXIS"} = onvif_device) do
    Logger.info("Auto configure AXIS camera")

    %AutoConfig{}
    |> maybe_create_and_configure_profiles(onvif_device)
  end

  def auto_configure(%{manufacturer: vendor} = onvif_device) do
    Logger.info("Auto configure #{vendor} camera")

    %AutoConfig{}
    |> do_configure_profiles(onvif_device)
  end

  def auto_configure(_onvif_device), do: %AutoConfig{}

  defp maybe_create_and_configure_profiles(auto_config, device) do
    case fetch_profiles(device) do
      {:ok, {main_profile, sub_profile}} ->
        Logger.info("[Onvif] Found main and sub profiles, start configuration")

        auto_config
        |> do_configure_profile(device, main_profile, :main_stream)
        |> do_configure_profile(device, sub_profile, :sub_stream)

      :ok ->
        Logger.info("[Onvif] Create main and sub profiles")

        case create_profiles(device) do
          {:ok, {main_profile, sub_profile}} ->
            auto_config
            |> do_configure_profile(device, main_profile, :main_stream)
            |> do_configure_profile(device, sub_profile, :sub_stream)

          {:error, reason} ->
            Logger.error("[Onvif] error while trying to create profiles: #{inspect(reason)}")
            auto_config
        end

      {:error, reason} ->
        Logger.error("[Onvif] error while trying to fetch profiles: #{inspect(reason)}")
        auto_config
    end
  end

  defp fetch_profiles(onvif_device) do
    with {:ok, profiles} <- Media2.get_profiles(onvif_device) do
      main_profile = Enum.find(profiles, &(&1.name == "ex_nvr_main"))
      sub_profile = Enum.find(profiles, &(&1.name == "ex_nvr_sub"))

      if main_profile, do: {:ok, {main_profile, sub_profile}}, else: :ok
    end
  end

  defp create_profiles(device) do
    with {:ok, sources} <- Media2.get_video_source_configurations(device),
         {:ok, configs} <- Media2.get_video_encoder_configurations(device),
         configs <- Enum.filter(configs, &(&1.use_count == 0)) |> Enum.take(2),
         {:ok, main} <-
           do_create_profile(device, "ex_nvr_main", hd(sources), Enum.at(configs, 0)),
         {:ok, sub} <- do_create_profile(device, "ex_nvr_sub", hd(sources), Enum.at(configs, 1)) do
      {:ok, {main, sub}}
    end
  end

  defp do_create_profile(_onvif_device, name, _video_source, nil) do
    Logger.error("[Onvif] could not create profile with name: #{name}, no video encoder config")
    {:ok, nil}
  end

  defp do_create_profile(onvif_device, name, video_source, video_encoder) do
    configs = [
      %{type: "VideoSource", token: video_source.reference_token},
      %{type: "VideoEncoder", token: video_encoder.reference_token}
    ]

    with {:ok, profile_token} <- Media2.create_profile(onvif_device, name, configs),
         {:ok, [profile]} <- Media2.get_profiles(onvif_device, token: profile_token) do
      {:ok, profile}
    end
  end

  defp do_configure_profiles(auto_config, onvif_device) do
    Logger.info("[Onvif] Configure profiles")

    case ExOnvif.Media2.get_profiles(onvif_device) do
      {:ok, profiles} ->
        auto_config
        |> do_configure_profile(onvif_device, Enum.at(profiles, 0), :main_stream)
        |> do_configure_profile(onvif_device, Enum.at(profiles, 1), :sub_stream)

      _error ->
        auto_config
    end
  end

  defp do_configure_profile(auto_config, _onvif_device, nil, _profile_type), do: auto_config

  defp do_configure_profile(auto_config, onvif_device, profile, stream_type) do
    config_options_result =
      ExOnvif.Media2.get_video_encoder_configuration_options(onvif_device,
        profile_token: profile.reference_token
      )

    with {:ok, configs} <- config_options_result,
         :ok <- set_video_encoder_config(onvif_device, profile, configs, stream_type) do
      Map.put(auto_config, stream_type, true)
    else
      {:error, reason} ->
        Logger.error("[Onvif] could not configure profile: #{inspect(reason)}")
        auto_config
    end
  end

  defp set_video_encoder_config(onvif_device, profile, configs, stream_type) do
    {codec, bit_rate, gov_length_coeff} =
      case stream_type do
        :main_stream -> {:h265, 3072, 4}
        :sub_stream -> {:h264, 572, 2}
      end

    config =
      Enum.find(configs, &(&1.encoding == codec)) ||
        Enum.find(configs, &(&1.encoding == :h264))

    frame_rate = select_frame_rate(config.frame_rates_supported)
    %VideoEncoder{} = video_encoder_configuration = profile.video_encoder_configuration

    video_encoder = %VideoEncoder{
      video_encoder_configuration
      | encoding: config.encoding,
        gov_length: trunc(frame_rate * gov_length_coeff),
        rate_control: %VideoEncoder.RateControl{
          bitrate_limit: bit_rate,
          constant_bitrate: false,
          frame_rate_limit: frame_rate
        },
        resolution: select_resolution(config.resolutions_available, stream_type)
    }

    case select_quality(onvif_device, config.quality_range) do
      nil -> video_encoder
      quality -> %VideoEncoder{video_encoder | quality: quality}
    end

    ExOnvif.Media2.set_video_encoder_configuration(onvif_device, video_encoder)
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
    case ExOnvif.Media2.get_profiles(onvif_device, token: profile_token, type: ["VideoEncoder"]) do
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

  defp select_resolution(resolutions, stream) do
    resolutions = Enum.sort_by(resolutions, & &1.height, :desc)

    case stream do
      :main_stream -> find_best_resolution(resolutions)
      _other -> Enum.drop_while(resolutions, &(&1.height > 1000 or &1.width > 1000)) |> hd()
    end
  end

  defp select_quality(%{manufacturer: "AXIS"}, _quality), do: 70
  defp select_quality(_device, %{max: max, min: min}) when is_nil(max) or is_nil(min), do: nil
  defp select_quality(_device, quality), do: Float.ceil((quality.max + quality.min) / 2)

  # prefer 4K resolutions with 16:9 aspect ratio
  defp find_best_resolution(resolutions) do
    Enum.reduce_while(resolutions, hd(resolutions), fn
      %{width: 3840, height: 2160} = res, _acc -> {:halt, res}
      %{height: 2160} = res, _acc -> {:cont, res}
      _res, acc -> {:cont, acc}
    end)
  end
end
