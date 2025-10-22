defmodule ExNVR.RemovableStorage.Mp4Concatinator do
  @moduledoc """
   1. process for just copying files to  
   2. this is concatinator

  """
  use GenServer

  alias ExNVR.Recordings

  @spec fetch_recordings(map(), atom(), binary(), binary()) :: any()
  def fetch_recordings(device, stream, start_date, end_date) do
    recordings =
      Recordings.get_recordings_between(device.id, :high, start_date, end_date)

    recordings_paths =
      recordings
      |> Enum.map(fn recording ->
        ["file #{Recordings.recording_path(device, recording.stream, recording)}\n"]
      end)
      |> List.flatten()
      |> then(&File.write("export.txt", &1))
  end

  # this makes concats mp4 and also moves to external storage
  @spec concat(String.t(), String.t()) :: any()
  def concat(footage_path, destination) do
    System.cmd("ffmpeg", [
      "-f",
      "concat",
      "-safe",
      "0",
      "-i",
      "#{footage_path}",
      "-c",
      "copy",
      "#{destination}",
      "-y"
    ])
    |> case do
      {"", 0} -> {:ok, :complete}
      _ -> {:error, "Concatination failed"}
    end
  end
end
