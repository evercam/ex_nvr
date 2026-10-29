defmodule ExNVR.Devices.Cameras.HttpClient.Milesight do
  @moduledoc """
  Client for Milesight camera
  """

  use ExNVR.Devices.Cameras.HttpClient

  require Logger

  alias ExNVR.Devices.Cameras.{DeviceInfo, ImageSettings, OSD, RemoteRecording, StreamProfile}
  alias ExNVR.HTTP

  @admin_path "/cgi-bin/admin/admin.cgi"
  @operator_path "/cgi-bin/operator/operator.cgi"
  @lpr_path "/cgi-bin/operator/operator.cgi?action=get.lpr.lastdata&format=inf"
  @lpr_image_path "/LPR"
  @search_path "/vb.htm"
  @download_path "/dataloader.cgi"
  @page_size 100
  @osd_fields ~w(streamIndex osdEnable osdString osdTextPosition osdDateTimeEnable osdDateTimePosition
                 osdDateTimeFormat osdFontSize osdFontColor osdBackgroundEnable osdBackgroundColor)
  # the camera hangs when searching long periods
  @search_window_seconds 12 * 3600

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

  @impl true
  def stream_profiles(url, opts) do
    url = url <> @operator_path <> "?action=get.video.general&format=json"

    HTTP.get(url, opts)
    |> handle_http_response(&parse_stream_profiles_response/1)
  end

  @impl true
  def set_stream_profile(url, %StreamProfile{} = profile, opts) do
    url = url <> @operator_path <> "?action=set.video.general&format=json"
    body = %{"streamList" => %{profile.name => map_stream_profile(profile)}}

    url
    |> HTTP.post(body, opts)
    |> handle_http_response(fn body ->
      case Jason.decode(body) do
        {:ok, parsed} -> parsed
        {:error, _reason} -> body
      end
    end)
  end

  @impl true
  def list_recordings(url, start_date, end_date, opts) do
    timezone = opts[:timezone] || "Etc/UTC"

    start_date
    |> search_windows(end_date)
    |> Enum.reduce_while({:ok, []}, fn {window_start, window_end}, {:ok, acc} ->
      params = [
        page: "sdexplorer",
        use_sid: 1,
        maintype: 0,
        subtype: -1,
        time_start: to_local_time(window_start, timezone),
        time_end: to_local_time(window_end, timezone),
        iDisplayLength: @page_size
      ]

      case search_recordings(url, params, 0, [], opts) do
        {:ok, rows} -> {:cont, {:ok, acc ++ rows}}
        error -> {:halt, error}
      end
    end)
    |> case do
      # recordings overlapping two windows are returned twice
      {:ok, rows} ->
        {:ok, rows |> Enum.map(&parse_recording(&1, timezone)) |> Enum.uniq_by(& &1.id)}

      error ->
        error
    end
  end

  @impl true
  def download_recording(url, %RemoteRecording{priv_data: priv_data} = recording, dest, opts) do
    timezone = opts[:timezone] || "Etc/UTC"

    query =
      URI.encode_query(
        dw: "sd",
        filename: recording.id,
        starttime: to_local_time(recording.start_date, timezone),
        endtime: to_local_time(recording.end_date, timezone),
        index: priv_data.index,
        sid: priv_data.sid,
        uuid: priv_data.uuid
      )

    case HTTP.download(url <> @download_path <> "?" <> query, dest, opts) do
      {:ok, %{status: 200}} ->
        :ok

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, reason} ->
        File.rm(dest)
        {:error, reason}
    end
  end

  @impl true
  def set_image_settings(url, %ImageSettings{} = settings, opts) do
    body =
      %{
        brightness: settings.brightness,
        contrast: settings.contrast,
        colorSaturation: settings.saturation
      }
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    (url <> @operator_path <> "?action=set.camera.setting&format=json")
    |> HTTP.post(body, opts)
    |> handle_http_response(& &1)
    |> case do
      {:ok, _body} -> :ok
      error -> error
    end
  end

  @impl true
  def set_osd(url, %OSD{} = osd, opts) do
    url = url <> @operator_path

    osd_config = %{
      "osdTextPosition" => osd_position(osd.position),
      "osdDateTimePosition" => osd_position(osd.position),
      "osdDateTimeFormat" => osd_date_format(osd.date_format),
      "osdFontSize" => osd_font_size(osd.font_size),
      "osdDateTimeEnable" => 1
    }

    # read-modify-write, the camera requires all the stream fields
    with {:ok, %{"osdInfoList" => streams}} <-
           (url <> "?action=get.video.advanced&format=json")
           |> HTTP.get(opts)
           |> handle_http_response(&decode_json/1),
         body = %{"osdInfoList" => Enum.map(streams, &update_stream_osd(&1, osd_config))},
         {:ok, _body} <-
           (url <> "?action=set.video.advanced&format=json")
           |> HTTP.post(body, opts)
           |> handle_http_response(& &1) do
      :ok
    else
      {:ok, body} -> {:error, {:invalid_response, body}}
      error -> error
    end
  end

  @doc """
  Release the search session (sid & uuid) created by `list_recordings/4`.
  """
  @spec release_search_session(binary(), binary(), binary(), Keyword.t()) :: :ok | {:error, any()}
  def release_search_session(url, sid, uuid, opts) do
    (url <> @search_path <> "?closemsfshandle=#{sid};#{uuid}")
    |> HTTP.get(opts)
    |> handle_http_response(& &1)
    |> case do
      {:ok, _body} -> :ok
      error -> error
    end
  end

  defp search_windows(start_date, end_date) do
    Stream.unfold(start_date, fn window_start ->
      if DateTime.before?(window_start, end_date) do
        window_end =
          Enum.min([DateTime.add(window_start, @search_window_seconds), end_date], DateTime)

        {{window_start, window_end}, window_end}
      end
    end)
  end

  defp search_recordings(url, params, offset, acc, opts) do
    query = URI.encode_query(params ++ [iDisplayStart: offset])

    (url <> @search_path <> "?" <> query)
    |> HTTP.get(opts)
    |> handle_http_response(&decode_json/1)
    |> case do
      {:ok, %{"aaData" => [first_row | _rest] = rows} = response} ->
        acc = acc ++ rows

        if length(acc) >= Map.get(response, "iTotalRecords", 0) do
          {:ok, acc}
        else
          # reuse the search session for subsequent pages
          {sid, uuid} = search_session(first_row)
          params = Keyword.merge(params, sid: sid, uuid: uuid)
          search_recordings(url, params, offset + @page_size, acc, opts)
        end

      {:ok, _response} ->
        {:ok, acc}

      error ->
        error
    end
  end

  defp parse_recording([filename, start_time, end_time, type, size, param, index], timezone) do
    {sid, uuid} = search_session(param)

    %RemoteRecording{
      id: filename,
      start_date: from_local_time(start_time, timezone),
      end_date: from_local_time(end_time, timezone),
      size: String.to_integer(size),
      type: recording_type(type),
      priv_data: %{sid: sid, uuid: uuid, index: index}
    }
  end

  # param is "sid&uuid", or "plate&sid&uuid" for LPR snapshots
  defp search_session([_filename, _start, _end, _type, _size, param, _index]),
    do: search_session(param)

  defp search_session(param) do
    [sid, uuid] = param |> String.split("&") |> Enum.take(-2)
    {sid, uuid}
  end

  defp recording_type("1"), do: :schedule
  defp recording_type("2"), do: :alarm
  defp recording_type(_type), do: :unknown

  defp to_local_time(datetime, timezone) do
    datetime
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp from_local_time(time, timezone) do
    time
    |> NaiveDateTime.from_iso8601!()
    |> DateTime.from_naive!(timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  defp decode_json(body) when is_map(body), do: body

  defp decode_json(body) do
    # Fix invalid JSON with no value, e.g. {"key":, "other_key": "value"} => {"key": null, "other_key": "value"}
    body = Regex.replace(~r/:\s*(?=[,}])/, body, ": null")
    Jason.decode!(body)
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
          video_config: %StreamProfile.VideoConfig{
            codec: profile_codec(stream_profile["profileCodec"]),
            codec_profile: profile(stream_profile["profileCodec"], stream_profile["profile"]),
            width: stream_profile["width"],
            height: stream_profile["height"],
            frame_rate: stream_profile["framerate"],
            bitrate: stream_profile["bitrate"],
            bitrate_mode: bitrate_mode(stream_profile["rateMode"]),
            gop: stream_profile["profileGop"],
            smart_codec: stream_profile["smartStreamEnable"] == 1
          }
        }
      end

    [
      mapper.("mainStream", get_in(response, ["streamList", "mainStream"])),
      mapper.("subStream", get_in(response, ["streamList", "subStream"])),
      mapper.("thirdStream", get_in(response, ["streamList", "thirdStream"]))
    ]
  end

  defp map_stream_profile(%StreamProfile{} = profile) do
    %{
      enable: if(profile.enabled, do: 1, else: 0),
      profileCodec: profile_codec_to_integer(profile.video_config.codec),
      profile: profile_profile_to_integer(profile.video_config.codec_profile),
      width: profile.video_config.width,
      height: profile.video_config.height,
      framerate: profile.video_config.frame_rate,
      bitrate: profile.video_config.bitrate,
      rateMode: bitrate_mode_to_integer(profile.video_config.bitrate_mode),
      profileGop: profile.video_config.gop,
      smartStreamEnable: if(profile.video_config.smart_codec, do: 1, else: 0)
    }
  end

  # only send the fields the camera web UI sends
  defp update_stream_osd(stream, osd_config) do
    stream
    |> Map.take(@osd_fields)
    |> Map.merge(osd_config)
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

  defp profile_codec(0), do: :h264
  defp profile_codec(1), do: :mpeg4
  defp profile_codec(2), do: :mjpeg
  defp profile_codec(3), do: :h265
  defp profile_codec(_other), do: :unknown

  defp profile_codec_to_integer(:h264), do: 0
  defp profile_codec_to_integer(:mpeg4), do: 1
  defp profile_codec_to_integer(:mjpeg), do: 2
  defp profile_codec_to_integer(:h265), do: 3
  defp profile_codec_to_integer(_other), do: 0

  defp profile(0, 0), do: "base"
  defp profile(0, 1), do: "main"
  defp profile(0, 2), do: "high"
  defp profile(_codec, _other), do: nil

  defp profile_profile_to_integer("base"), do: 0
  defp profile_profile_to_integer("main"), do: 1
  defp profile_profile_to_integer("high"), do: 2
  defp profile_profile_to_integer(_other), do: 0

  defp bitrate_mode(0), do: :cbr
  defp bitrate_mode(1), do: :vbr
  defp bitrate_mode(_other), do: nil

  defp bitrate_mode_to_integer(:cbr), do: 0
  defp bitrate_mode_to_integer(:vbr), do: 1
  defp bitrate_mode_to_integer(_other), do: 0

  defp osd_position(:top_left), do: 0
  defp osd_position(:top_right), do: 1
  defp osd_position(:bottom_left), do: 2
  defp osd_position(:bottom_right), do: 3

  defp osd_date_format(:ymd), do: 0
  defp osd_date_format(:mdy), do: 1
  defp osd_date_format(:dmy), do: 2

  defp osd_font_size(:smallest), do: 0
  defp osd_font_size(:small), do: 1
  defp osd_font_size(:medium), do: 2
  defp osd_font_size(:large), do: 3
  defp osd_font_size(:largest), do: 4
  defp osd_font_size(:auto), do: 5

  defp handle_http_response({:ok, %{status: status, body: body}}, parser_fn)
       when status >= 200 and status < 300 do
    {:ok, parser_fn.(body)}
  end

  defp handle_http_response({:ok, %{status: status, body: body}}, _parser_fn),
    do: {:error, {status, body}}

  defp handle_http_response(error, _parser_fn), do: error
end
