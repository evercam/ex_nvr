defmodule ExNVR.Recordings.Reindexer do
  @moduledoc """
  Rebuild recordings and runs of a device from the metadata stored in the mp4 files.

  Files without metadata or that cannot be read are skipped.
  """

  require Logger

  alias ExMP4.Reader
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.Pipeline.Output.Storage
  alias ExNVR.Repo

  @max_gap_us 50_000

  @recording_fields [:device_id, :stream, :filename, :start_date, :end_date, :run_id]
  # keep the number of query parameters under sqlite limit
  @insert_batch_size 1_000

  @type scan_opts :: [save: boolean()]

  @doc """
  Scan the recordings of the device stored in `path`.

  Options:
    * `save` - Store the runs and recordings in the database, runs get new ids. Defaults to `false`.
  """
  @spec scan(Path.t(), binary(), scan_opts()) :: {[Run.t()], [Recording.t()]}
  def scan(path, device_id, opts \\ []) do
    device = %Device{id: device_id, storage_config: %Device.StorageConfig{address: path}}
    disk_serial = ExNVR.Disk.serial(path)

    runs_with_recordings =
      [:high, :low]
      |> Stream.flat_map(&list_files(device, &1))
      |> Task.async_stream(fn {stream, file} -> read_recording(device_id, stream, file) end,
        ordered: false,
        timeout: :infinity
      )
      |> Stream.filter(&match?({:ok, %Recording{}}, &1))
      |> Stream.map(&elem(&1, 1))
      |> sort_by_date()
      |> Enum.group_by(&{&1.stream, &1.run_id})
      |> Enum.map(fn {{stream, run_id}, recs} ->
        recs = join_contiguous(recs)

        run = %Run{
          id: run_id,
          device_id: device_id,
          stream: stream,
          start_date: List.first(recs).start_date,
          end_date: Enum.max_by(recs, & &1.end_date, DateTime).end_date,
          active: false,
          disk_serial: disk_serial
        }

        {run, recs}
      end)
      |> maybe_save(opts[:save])

    runs = runs_with_recordings |> Enum.map(&elem(&1, 0)) |> sort_by_date()
    recordings = runs_with_recordings |> Enum.flat_map(&elem(&1, 1)) |> sort_by_date()

    {runs, recordings}
  end

  defp maybe_save(runs_with_recordings, true) do
    {:ok, result} =
      Repo.transaction(fn -> Enum.map(runs_with_recordings, &insert_run/1) end,
        timeout: :infinity
      )

    result
  end

  defp maybe_save(runs_with_recordings, _save), do: runs_with_recordings

  defp insert_run({run, recordings}) do
    run = Repo.insert!(%{run | id: nil})

    recordings =
      recordings
      |> Stream.map(&(&1 |> Map.take(@recording_fields) |> Map.put(:run_id, run.id)))
      |> Stream.chunk_every(@insert_batch_size)
      |> Enum.flat_map(fn batch ->
        {_count, inserted} = Repo.insert_all(Recording, batch, returning: true)
        inserted
      end)

    {run, recordings}
  end

  defp sort_by_date(items) do
    Enum.sort_by(items, &{&1.stream, DateTime.to_unix(&1.start_date, :microsecond)})
  end

  # recordings of the same run are contiguous, absorb the small gap/overlap due to the media duration
  defp join_contiguous(recordings) do
    recordings
    |> Enum.chunk_every(2, 1)
    |> Enum.map(fn
      [rec, next] ->
        gap = DateTime.diff(next.start_date, rec.end_date, :microsecond)
        if abs(gap) <= @max_gap_us, do: %{rec | end_date: next.start_date}, else: rec

      [rec] ->
        rec
    end)
  end

  defp list_files(device, stream) do
    device
    |> Device.recording_dir(stream)
    |> Path.join("*/*/*/*/*.mp4")
    |> Path.wildcard()
    |> Stream.map(&{stream, &1})
  end

  defp read_recording(device_id, stream, file) do
    with {:ok, start_date} <- start_date_from_filename(file),
         {:ok, run_id, duration} <- read_metadata(file) do
      %Recording{
        device_id: device_id,
        stream: stream,
        filename: Path.basename(file),
        start_date: start_date,
        end_date: DateTime.add(start_date, duration, :microsecond),
        run_id: run_id
      }
    else
      {:error, reason} ->
        Logger.warning("[Reindexer] skip file #{file}: #{inspect(reason)}")
        nil
    end
  end

  defp start_date_from_filename(file) do
    with {unix_us, ""} <- file |> Path.basename(".mp4") |> Integer.parse(),
         {:ok, date} <- DateTime.from_unix(unix_us, :microsecond) do
      {:ok, date}
    else
      _error -> {:error, :invalid_filename}
    end
  end

  defp read_metadata(file) do
    with {:ok, reader} <- Reader.new(file) do
      result = do_read_metadata(reader)
      Reader.close(reader)
      result
    end
  rescue
    error -> {:error, error}
  end

  defp do_read_metadata(reader) do
    with %{data: data} <-
           Enum.find(reader.uuid, :no_metadata, &(&1.type == Storage.metadata_uuid())),
         {:ok, %{"run_id" => run_id}} when is_integer(run_id) <- Jason.decode(data) do
      {:ok, run_id, Reader.duration(reader, :microsecond)}
    else
      :no_metadata -> {:error, :no_metadata}
      _error -> {:error, :invalid_metadata}
    end
  end
end
