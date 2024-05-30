defmodule ExNVR.Devices.Cameras.HttpClient.Milesight do
  @moduledoc """
  Client for Milesight camera
  """

  use ExNVR.Devices.Cameras.HttpClient

  require Logger

  alias ExNVR.HTTP

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

      {:ok, response} ->
        {:error, response}

      {:error, reason} ->
        {:error, reason}
    end
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
end
