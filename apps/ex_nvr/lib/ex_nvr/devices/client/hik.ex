defmodule ExNVR.Devices.Client.Hik do
  @moduledoc """
  Client for Hikvision camera
  """
  require Logger

  import SweetXml

  alias ExNVR.HTTP

  @lpr_path "/ISAPI/Traffic/channels/1/vehicledetect/plates"
  @lpr_image_path "/doc/ui/images/plate"

  def fetch_anpr(url, opts) do
    full_url = url <> @lpr_path

    request_body =
      "<AfterTime><picTime>#{get_last_event_timestamp(opts[:last_event_timestamp])}</picTime></AfterTime>"

    case HTTP.post(full_url, request_body, opts) do
      {:ok, %{body: body, status: 200}} ->
        records = parse_response(body, opts[:timezone])
        plates = fetch_plate_image(records, url, opts)

        {:ok, records, plates}

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_last_event_timestamp(nil), do: 0

  defp get_last_event_timestamp(last_event_timestamp),
    do: DateTime.add(last_event_timestamp, 1) |> Calendar.strftime("%Y%m%d%H%M%S")

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
