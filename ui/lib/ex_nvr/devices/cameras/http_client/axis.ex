defmodule ExNVR.Devices.Cameras.HttpClient.Axis do
  @moduledoc """
  Client for AXIS camera
  """
  use ExNVR.Devices.Cameras.HttpClient

  require Logger

  import SweetXml

  alias ExNVR.Devices.Cameras.{DeviceInfo, StreamProfile}
  alias ExNVR.HTTP

  @basic_info "/axis-cgi/basicdeviceinfo.cgi"
  @stream_profiles "/axis-cgi/streamprofile.cgi"
  @lpr_path "/local/fflprapp/search.cgi"
  @lpr_image_path_prefix "/local/fflprapp/"

  @timestamp_regex ~r/(\d+-\d+-\d+ \d+:\d+:\d+).*/

  @impl true
  def fetch_lpr_event(url, opts) do
    timestamp =
      opts[:last_event_timestamp] && DateTime.to_unix(opts[:last_event_timestamp], :microsecond)

    full_url = url <> @lpr_path <> "?TimestampFrom=#{timestamp}"

    case HTTP.get(full_url, opts) do
      {:ok, %{body: body, status: 200}} ->
        records = parse_response(body, opts[:timezone])
        plates = fetch_plate_image(records, url, opts)
        {:ok, Enum.map(records, &update_pic_name/1), plates}

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def device_info(url, opts) do
    url = url <> @basic_info
    body = %{"apiVersion" => "1.2", "method" => "getAllProperties"}

    url
    |> HTTP.post(body, opts)
    |> parse_http_response(&parse_device_info_response/1)
  end

  @impl true
  def stream_profiles(url, opts) do
    url = url <> @stream_profiles
    body = %{"apiVersion" => "1.0", "method" => "list", "params" => %{"streamProfileName" => []}}

    url
    |> HTTP.post(body, opts)
    |> parse_http_response(&parse_stream_profile_response/1)
  end

  defp parse_response(body, timezone) do
    SweetXml.xpath(
      body,
      ~x"//event"l,
      capture_time: ~x"./TS/text()"s |> transform_by(&to_datetime/1),
      capture_time2: ~x"./MOD_TS/text()"s |> transform_by(&to_datetime(&1, timezone)),
      plate_number: ~x"./LPR/text()"s,
      pic_name: ~x"./LP_BMP/text()"s,
      direction: ~x"./DIRECTION/text()"s |> transform_by(&parse_direction/1),
      vehicle_type: ~x"./CAR_M_TYPE/text()"s |> transform_by(&String.downcase/1),
      vehicle_color: ~x"./CAR_COLOR/text()"s |> transform_by(&String.downcase/1),
      confidence: ~x"./CAR_CONF/text()"F
    )
    |> Enum.map(fn response ->
      metadata_keys = [:vehicle_type, :vehicle_color, :confidence]

      response
      |> Map.put(:metadata, Map.take(response, metadata_keys))
      |> Map.drop(metadata_keys)
    end)
    |> Enum.map(fn response ->
      cond do
        response.capture_time == 0 and response.capture_time2 == 0 ->
          raise("""
          LPR: could not parse unix timestamp
          Response body: #{body}
          """)

        response.capture_time == 0 ->
          response
          |> Map.put(:capture_time, response.capture_time2)
          |> Map.delete(:capture_time2)

        true ->
          Map.delete(response, :capture_time2)
      end
    end)
  end

  defp parse_device_info_response(body) do
    data = body["data"]["propertyList"]

    %DeviceInfo{
      vendor: "AXIS",
      name: data["ProductFullName"],
      model: data["ProdNbr"],
      serial: data["SerialNumber"],
      firmware_version: data["Version"]
    }
  end

  defp parse_stream_profile_response(body) do
    body["data"]["streamProfile"]
    |> Enum.map(fn entry ->
      params = URI.decode_query(entry["parameters"])

      [width, height] =
        params
        |> Map.get("resolution", "1920x1080")
        |> String.split("x")
        |> Enum.map(&String.to_integer/1)

      %StreamProfile{
        id: entry["name"],
        name: entry["name"],
        enabled: true,
        codec: Map.get(params, "videocodec", "h264"),
        profile: nil,
        frame_rate: Map.get(params, "fps", "0") |> String.to_integer(),
        width: width,
        height: height,
        gop: Map.get(params, "videokeyframeinterval", "32") |> String.to_integer(),
        bitrate: 0,
        bitrate_mode: Map.get(params, "videobitratemode", "abr"),
        smart_codec: false
      }
    end)
  end

  defp to_datetime(unix_timestamp) do
    with {unix_timestamp, ""} <- Integer.parse(unix_timestamp),
         {:error, :invalid_unix_time} <- DateTime.from_unix(unix_timestamp, :millisecond),
         {:error, :invalid_unix_time} <- DateTime.from_unix(unix_timestamp, :microsecond) do
      0
    else
      :error -> 0
      {:ok, datetime} -> datetime
    end
  end

  defp to_datetime(date, timezone) do
    date_without_timezone = Regex.replace(@timestamp_regex, date, "\\g{1}")

    case NaiveDateTime.from_iso8601(date_without_timezone) do
      {:ok, date} -> DateTime.from_naive!(date, timezone) |> DateTime.shift_zone!("Etc/UTC")
      _error -> 0
    end
  end

  defp parse_direction("2"), do: "in"
  defp parse_direction("3"), do: "away"
  defp parse_direction(_direction), do: "unknown"

  # convert the pic_name from a path to a filename
  defp update_pic_name(record) do
    pic_name =
      record.pic_name
      |> String.replace("&amp;", "&")
      |> URI.parse()
      |> then(&URI.decode_query(&1.query))
      |> Map.get("name")
      |> String.replace("/", "_")

    %{record | pic_name: pic_name}
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
    url = url <> @lpr_image_path_prefix <> pic_image

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

  defp parse_http_response({:ok, %{body: body, status: status}}, parse_fn)
       when status >= 200 and status < 300 do
    {:ok, parse_fn.(body)}
  end

  defp parse_http_response({:ok, %{body: body, status: status}}, _parse_fn) do
    {:error, {status, body}}
  end

  defp parse_http_response(error, _parse_fn), do: error
end
