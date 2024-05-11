defmodule ExNVR.Devices.CameraClient.Axis do
  @moduledoc """
  Client for AXIS camera
  """
  require Logger

  import SweetXml

  alias ExNVR.HTTP

  @lpr_path "/local/fflprapp/search.cgi"
  @lpr_image_path_prefix "/local/fflprapp/"
  @timestamp_regex ~r/(\d+-\d+-\d+ \d+:\d+:\d+).*/

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
end
