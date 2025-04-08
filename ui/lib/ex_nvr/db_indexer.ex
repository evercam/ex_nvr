defmodule ExNVR.DBIndexer do
  @moduledoc """
  This module is responsible for indexing the database.

  It scans the recordings files and build the recordings and runs metadata.
  """

  alias ExNVR.Model.Device

  @spec index(Device.t(), DateTime.t() | nil, DateTime.t() | nil) :: {list(), list()}
  def index(device, start_date, end_date) do
    recordings = get_recordings(device, start_date, end_date)
    runs = recordings_to_runs(recordings)

    {recordings, runs}
  end

  defp get_recordings(device, start_date, end_date) do
    Path.join([Device.recording_dir(device), "**", "*.mp4"])
    |> Path.wildcard()
    |> Enum.sort()
    |> Stream.map(fn path ->
      %{
        device_id: device.id,
        stream: :high,
        filename: Path.basename(path),
        start_date:
          Path.basename(path, ".mp4")
          |> String.to_integer()
          |> DateTime.from_unix!(:microsecond),
        end_date: nil
      }
    end)
    |> filter_by_start_date(start_date)
    |> filter_by_end_date(end_date)
    |> Task.async_stream(&set_recording_end_date(device, &1), timeout: :infinity)
    |> Stream.map(&elem(&1, 1))
    |> Enum.reject(&(DateTime.compare(&1.start_date, &1.end_date) == :eq))
  end

  defp set_recording_end_date(device, recording) do
    path = ExNVR.Recordings.recording_path(device, recording)

    case ExMP4.Reader.new(path) do
      {:ok, reader} ->
        duration = reader.duration && ExMP4.Reader.duration(reader, :microsecond)
        %{recording | end_date: DateTime.add(recording.start_date, duration || 0, :microsecond)}

      _other ->
        %{recording | end_date: recording.start_date}
    end
  end

  defp recordings_to_runs([]), do: []

  defp recordings_to_runs([first_rec | _recs] = recordings) do
    run = %{
      device_id: first_rec.device_id,
      start_date: first_rec.start_date,
      end_date: first_rec.end_date
    }

    recordings
    |> Stream.chunk_every(2, 1, :discard)
    |> Enum.reduce([run], fn [rec1, rec2], [run | runs] ->
      if DateTime.diff(rec2.start_date, rec1.end_date, :millisecond) >= 1000 do
        new_run = %{
          device_id: rec2.device_id,
          start_date: rec2.start_date,
          end_date: rec2.end_date
        }

        [new_run, run | runs]
      else
        [%{run | end_date: rec2.end_date} | runs]
      end
    end)
    |> Enum.reverse()
  end

  defp filter_by_start_date(stream, nil), do: stream

  defp filter_by_start_date(stream, start_date) do
    Stream.drop_while(stream, &(DateTime.compare(&1.start_date, start_date) == :lt))
  end

  defp filter_by_end_date(stream, nil), do: stream

  defp filter_by_end_date(stream, end_date) do
    Stream.take_while(stream, &(DateTime.compare(&1.start_date, end_date) == :lt))
  end
end
