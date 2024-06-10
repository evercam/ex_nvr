defmodule ExNVR.Devices.Cameras.HttpClient.Milesight do
  @moduledoc """
  Client for Milesight camera
  """

  use ExNVR.Devices.Cameras.HttpClient

  require Logger

  alias ExNVR.Devices.Cameras.{DeviceInfo, StreamProfile}
  alias ExNVR.HTTP

  @admin_path "/cgi-bin/admin/admin.cgi"
  @operator_path "/cgi-bin/operator/operator.cgi"
  @lpr_path "/cgi-bin/operator/operator.cgi?action=get.lpr.lastdata&format=inf"
  @lpr_image_path "/LPR"

  @impl true
  def fetch_lpr_event(url, opts) do
    full_url = url <> @lpr_path

    case HTTP.get(full_url, opts) do
      {:ok, %Req.Response{body: body, status: 200}} ->
        records = parse_response(body, opts)
        plates = fetch_plate_image(records, url, opts)
        {:ok, records, plates}

      {:ok, %{body: body, status: status}} ->
        {:error, {status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def device_info(url, opts) do
    url = url <> @admin_path <> "?action=get.system.information&format=json"

    HTTP.get(url, opts)
    |> handle_http_response(&parse_system_response/1)
  end

  def stream_profiles(url, opts) do
    url = url <> @operator_path <> "?action=get.video.general&format=json"

    HTTP.get(url, opts)
    |> handle_http_response(&parse_stream_profiles_response/1)
  end

  defp parse_system_response(body) do
    response = Jason.decode!(body)

    %DeviceInfo{
      vendor: "Milesight Technology Co.,Ltd.",
      name: response["deviceName"],
      model: response["model"],
      serial: response["snCode"],
      firmware_version: response["firmwareVersion"]
    }
  end

  defp parse_stream_profiles_response(body) do
    response = Jason.decode!(body)

    mapper =
      fn name, stream_profile ->
        %StreamProfile{
          id: stream_profile["url"],
          name: name,
          enabled: stream_profile["enable"] != 0,
          codec: profile_codec(stream_profile["profileCodec"]),
          profile: profile(stream_profile["profileCodec"], stream_profile["profile"]),
          width: stream_profile["width"],
          height: stream_profile["height"],
          frame_rate: stream_profile["framerate"],
          bitrate: stream_profile["bitrate"],
          bitrate_mode: bitrate_mode(stream_profile["rateMode"]),
          gop: stream_profile["profileGop"],
          smart_codec: stream_profile["smartStreamEnable"] == 1
        }
      end

    [
      mapper.("mainStream", get_in(response, ["streamList", "mainStream"])),
      mapper.("subStream", get_in(response, ["streamList", "subStream"])),
      mapper.("thirdStream", get_in(response, ["streamList", "thirdStream"]))
    ]
  end

  defp parse_response(body, opts) do
    body
    |> String.split("\n")
    |> Enum.chunk_every(10, 10, :discard)
    |> Enum.map(&parse_entry/1)
    |> Enum.map(&rename_keys/1)
    |> Enum.map(fn record ->
      capture_time = parse_capture_time(record.capture_time, opts[:timezone])
      %{record | capture_time: capture_time}
    end)
    |> Enum.filter(fn record ->
      is_nil(opts[:last_event_timestamp]) ||
        DateTime.after?(record.capture_time, opts[:last_event_timestamp])
    end)
  end

  defp parse_entry(entry_lines) do
    entry_lines
    |> Enum.map(fn line ->
      [key, value] = String.split(line, "=", parts: 2)

      [key, value] = [
        String.replace(key, ~r/_(\d+)$/, "") |> String.to_atom(),
        String.trim(value)
      ]

      {key, value}
    end)
    |> Map.new()
  end

  defp rename_keys(entry) do
    %{
      capture_time: entry[:time],
      plate_number: entry[:plate],
      pic_name: entry[:path],
      direction: parse_direction(entry[:direction])
    }
  end

  defp parse_direction("1"), do: "in"
  defp parse_direction("2"), do: "away"
  defp parse_direction(_), do: "unknown"

  defp parse_capture_time(date_string, timezone) do
    [date, time] = String.split(date_string, " ")

    DateTime.new!(
      Date.from_iso8601!(date),
      Time.from_iso8601!(time),
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
    url = "#{url}#{@lpr_image_path}/#{pic_image}"

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

  defp profile_codec(0), do: "H264"
  defp profile_codec(1), do: "MPEG4"
  defp profile_codec(2), do: "MJPEG"
  defp profile_codec(3), do: "H265"
  defp profile_codec(_other), do: "n/a"

  defp profile(0, 0), do: "base"
  defp profile(0, 1), do: "main"
  defp profile(0, 2), do: "high"
  defp profile(_codec, _other), do: "n/a"

  defp bitrate_mode(0), do: "CBR"
  defp bitrate_mode(1), do: "VBR"
  defp bitrate_mode(_other), do: "n/a"

  defp handle_http_response({:ok, %{status: status, body: body}}, parser_fn)
       when status >= 200 and status < 300 do
    {:ok, parser_fn.(body)}
  end

  defp handle_http_response({:ok, %{status: status, body: body}}, _parser_fn),
    do: {:error, {status, body}}

  defp handle_http_response(error, _parser_fn), do: error
end
