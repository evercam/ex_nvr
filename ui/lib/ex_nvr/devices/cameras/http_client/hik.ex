defmodule ExNVR.Devices.Cameras.HttpClient.Hik do
  @moduledoc """
  Client for Hikvision camera
  """

  use ExNVR.Devices.Cameras.HttpClient

  require Logger

  import SweetXml

  alias ExNVR.HTTP

  @lpr_path "/ISAPI/Traffic/channels/1/vehicledetect/plates"
  @lpr_image_path "/doc/ui/images/plate"
  @device_info "/ISAPI/System/deviceinfo"
  @stream_config_path "/ISAPI/Streaming/channels"

  @impl true
  def fetch_lpr_event(url, opts) do
    last_event_timestamp = last_event_timestamp(opts[:last_event_timestamp], opts[:timezone])
    request_body = "<AfterTime><picTime>#{last_event_timestamp}</picTime></AfterTime>"

    case HTTP.post(url <> @lpr_path, request_body, opts) do
      {:ok, %Req.Response{body: body, status: 200}} ->
        records = parse_response(body, opts[:timezone])
        plates = fetch_plate_image(records, url, opts)

        {:ok, records, plates}

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def device_info(url, opts) do
    case HTTP.get(url <> @device_info, opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, parse_device_info_response(body)}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def stream_profiles(url, opts) do
    case HTTP.get(url <> @stream_config_path, opts) do
      {:ok, %{status: 200, body: body}} -> {:ok, parse_stream_response(body)}
      {:ok, response} -> {:error, response}
      {:error, reason} -> {:error, reason}
    end
  end

  defp last_event_timestamp(nil, _timezone), do: 0

  defp last_event_timestamp(last_event_timestamp, timezone) do
    last_event_timestamp
    |> DateTime.shift_zone!(timezone)
    |> DateTime.add(1)
    |> Calendar.strftime("%Y%m%d%H%M%S")
  end

  defp parse_response(body, timezone) do
    body
    |> SweetXml.xpath(
      ~x"//Plate"l,
      capture_time: ~x"./captureTime/text()"s,
      plate_number: ~x"./plateNumber/text()"s,
      pic_name: ~x"./picName/text()"s,
      direction: ~x"./direction/text()"s
    )
    |> Enum.map(fn record ->
      capture_time = parse_capture_time(record.capture_time, timezone)
      direction = parse_direction(record.direction)
      %{record | capture_time: capture_time, direction: direction}
    end)
  end

  defp parse_device_info_response(body) do
    body
    |> SweetXml.xpath(
      ~x"//DeviceInfo",
      name: ~x"./deviceName/text()"s,
      model: ~x"./model/text()"s,
      serial: ~x"./serialNumber/text()"s,
      firmware_version: ~x"./firmwareVersion/text()"s
    )
    |> Map.put(:vendor, "HIKVISION")
    |> then(&struct(ExNVR.Devices.Cameras.DeviceInfo, &1))
  end

  defp parse_stream_response(body) do
    body
    |> SweetXml.xpath(
      ~x"//StreamingChannel"l,
      id: ~x"./id/text()"i,
      enabled: ~x"./enabled/text()"s |> transform_by(&String.to_existing_atom/1),
      codec: ~x"./Video/videoCodecType/text()"s |> transform_by(&String.replace(&1, ".", "")),
      width: ~x"./Video/videoResolutionWidth/text()"I,
      height: ~x"./Video/videoResolutionHeight/text()"I,
      bitrate: ~x"./Video/constantBitRate/text()"I,
      bitrate_mode: ~x"./Video/videoQualityControlType/text()"s,
      frame_rate: ~x"./Video/maxFrameRate/text()"I |> transform_by(&(&1 / 100)),
      gop: ~x"./Video/GovLength/text()"I,
      smart_codec: ~x"./Video/SmartCodec/enabled/text()"s,
      h264_profile: ~x"./Video/H264Profile/text()"s,
      h265_profile: ~x"./Video/H265Profile/text()"s
    )
    |> Enum.map(fn config ->
      smart_codec =
        case config.smart_codec do
          "" -> false
          value -> String.to_existing_atom(value)
        end

      profile =
        case config.codec do
          "H264" -> String.downcase(config.h264_profile)
          "H265" -> String.downcase(config.h265_profile)
          _other -> nil
        end

      config = Map.merge(config, %{smart_codec: smart_codec, profile: profile})
      struct(ExNVR.Devices.Cameras.StreamProfile, config)
    end)
  end

  defp parse_direction("forward"), do: "in"
  defp parse_direction("reverse"), do: "away"
  defp parse_direction(_), do: "unknown"

  defp parse_capture_time(
         <<year::binary-size(4), month::binary-size(2), day::binary-size(2), "T",
           hour::binary-size(2), minute::binary-size(2), second::binary-size(2), _tz::binary>>,
         timezone
       ) do
    DateTime.new!(
      Date.from_iso8601!("#{year}-#{month}-#{day}"),
      Time.from_iso8601!("#{hour}:#{minute}:#{second}"),
      timezone
    )
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp fetch_plate_image(records, url, opts) do
    records
    |> Task.async_stream(&do_fetch_image(url, &1.pic_name, opts),
      on_timeout: :kill_task,
      max_concurrency: 4
    )
    |> Stream.map(fn
      {:ok, result} -> result
      {:exit, _value} -> nil
    end)
    |> Enum.to_list()
  end

  defp do_fetch_image(url, pic_image, opts) do
    url = "#{url}#{@lpr_image_path}/#{pic_image}.jpg"

    case HTTP.get(url, opts) do
      {:ok, %{status: 200, body: body}} -> body
      {:ok, response} -> log_error(url, response)
      {:error, reason} -> log_error(url, reason)
    end
  end

  defp log_error(url, reason) do
    Logger.error("""
    could not fetch lpr image
    url: #{url}
    reason: #{inspect(reason)}
    """)

    nil
  end
end
