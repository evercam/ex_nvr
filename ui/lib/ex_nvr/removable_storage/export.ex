defmodule ExNVR.RemovableStorage.Export do
  @moduledoc """
   1. process for just copying files to  
   2. this is concatinator

    state -> should have the recordings

  """
  @type export_type() :: :one | :full

  @rec_list_path "export.txt"

  alias ExNVR.Recordings

  @spec fetch_and_list_recordings(map(), atom(), binary(), binary()) :: any()
  def fetch_and_list_recordings(device, stream, start_date, end_date) do
    recordings =
      Recordings.get_recordings_between(device.id, stream, start_date, end_date)

    response =
      recordings
      |> Enum.map(fn recording ->
        ["file #{Recordings.recording_path(device, recording.stream, recording)}\n"]
      end)
      |> List.flatten()
      |> then(&File.write(@rec_list_path, &1))

    {response, recordings}
  end

  # this makes concats mp4 and also moves to external storage
  @spec concat_and_export_to_usb(export_type(), String.t(), Date.t(), Date.t(), list(), map()) ::
          {:ok, :complete} | {:error, String.t()}
  def concat_and_export_to_usb(:full, destination, start_date, end_date, _recordings, _device) do
    System.cmd("ffmpeg", [
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      "#{@rec_list_path}",
      "-c",
      "copy",
      "#{destination}/#{format_date(start_date)}_to_#{format_date(end_date)}.mp4",
      "-y"
    ])
    |> case do
      {"", 0} -> {:ok, :complete}
      _ -> {:error, "Export to usb failed"}
    end
  end

  def concat_and_export_to_usb(:one, destination, _start_date, _end_date, recordings, device) do
    recordings
    |> Enum.map(fn rec ->
      System.cmd("cp", [
        "#{Recordings.recording_path(device, rec.stream, rec)}",
        "#{destination}/#{format_date(rec.start_date)}_to_#{format_date(rec.end_date)}"
      ])
    end)
  end

  @spec format_date(String.t() | Date.t()) :: String.t()
  defp format_date(date) when is_binary(date) do
    date
    |> String.replace(":", "-")
  end

  defp format_date(date) do
    date
    |> DateTime.to_string()
    |> format_date()
  end
end
