defmodule ExNVR.Recordings.Backfiller do
  @moduledoc """
  Fill the recording gaps of a device with footage downloaded from the camera storage (e.g. SD card).

  The intervals to fill are the intersection of the footage available on the camera
  and the gaps in the NVR runs. The downloaded footage is split into chunks starting
  on keyframes and stored as regular recordings (main stream only).
  """

  require Logger

  import ExMP4.Helper, only: [timescalify: 3]

  alias ExMP4.{Box, Reader, Track, Writer}
  alias ExNVR.Devices
  alias ExNVR.Devices.Cameras.RemoteRecording
  alias ExNVR.Model.{Device, Run}
  alias ExNVR.Pipeline.Output.Storage
  alias ExNVR.Recordings

  @default_min_gap 600
  @default_chunk_duration 60
  # footage within this gap of the current run end is added to the same run
  @max_run_gap_us 1_000_000
  # camera recordings dates have a second precision
  @max_camera_gap 1

  @type opts :: [min_gap: non_neg_integer(), chunk_duration: pos_integer()]

  @doc """
  Backfill the gaps of the device between `start_date` and `end_date`.

  See `fillable_intervals/4` for how the intervals are selected.

  Options:
    * `min_gap` - ignore gaps shorter than this value in seconds. Defaults to `#{@default_min_gap}`.
    * `chunk_duration` - target duration of each recording in seconds. Defaults to `#{@default_chunk_duration}`.
  """
  @spec run(Device.t(), DateTime.t(), DateTime.t(), opts()) :: {:ok, [Run.t()]} | {:error, any()}
  def run(%Device{} = device, start_date, end_date, opts \\ []) do
    tmp_dir = Path.join(Device.base_dir(device), "tmp")
    File.mkdir_p!(tmp_dir)

    state = %{
      device: device,
      tmp_dir: tmp_dir,
      chunk_duration: Keyword.get(opts, :chunk_duration, @default_chunk_duration) * 1_000_000,
      gap_end: nil,
      cursor: nil,
      chunk: nil,
      run: nil,
      runs: []
    }

    min_gap = Keyword.get(opts, :min_gap, @default_min_gap)

    with {:ok, intervals} <- fillable_intervals(device, start_date, end_date, min_gap) do
      {:ok, Enum.flat_map(intervals, &backfill_gap(state, &1))}
    end
  end

  @doc """
  Get the intervals between `start_date` and `end_date` where footage is available
  on the camera but missing in the NVR.

  The camera recordings are listed once for the whole period, the NVR gaps are only
  computed in the period covered by the camera. Intervals shorter than `min_gap` seconds are ignored.
  """
  @spec fillable_intervals(Device.t(), DateTime.t(), DateTime.t(), non_neg_integer()) ::
          {:ok, [{DateTime.t(), DateTime.t()}]} | {:error, any()}
  def fillable_intervals(%Device{} = device, start_date, end_date, min_gap) do
    end_date = Enum.min([end_date, DateTime.utc_now()], DateTime)

    with {:ok, camera_recordings} <-
           Devices.list_camera_recordings(device, start_date, end_date) do
      intervals =
        camera_recordings
        |> camera_intervals(start_date, end_date)
        |> missing_in_nvr(device)
        |> Enum.filter(fn {i_start, i_end} -> DateTime.diff(i_end, i_start) >= min_gap end)

      {:ok, intervals}
    end
  end

  @doc """
  Get the intervals between `start_date` and `end_date` not covered by any run.

  Intervals shorter than `min_gap` seconds are ignored.
  """
  @spec gaps(Device.t(), DateTime.t(), DateTime.t(), non_neg_integer()) :: [
          {DateTime.t(), DateTime.t()}
        ]
  def gaps(%Device{} = device, start_date, end_date \\ DateTime.utc_now(), min_gap) do
    %{device_id: device.id, start_date: start_date, end_date: end_date}
    |> Recordings.list_runs(:high)
    |> Enum.reduce({start_date, []}, fn run, {cursor, gaps} ->
      gaps =
        if DateTime.after?(run.start_date, cursor),
          do: [{cursor, run.start_date} | gaps],
          else: gaps

      {Enum.max([cursor, run.end_date], DateTime), gaps}
    end)
    |> then(fn {cursor, gaps} ->
      if DateTime.before?(cursor, end_date), do: [{cursor, end_date} | gaps], else: gaps
    end)
    |> Enum.reverse()
    |> Enum.filter(fn {gap_start, gap_end} -> DateTime.diff(gap_end, gap_start) >= min_gap end)
  end

  defp backfill_gap(state, {gap_start, gap_end}) do
    case Devices.list_camera_recordings(state.device, gap_start, gap_end) do
      {:ok, camera_recordings} ->
        Logger.info(
          "[Backfiller] fill gap #{gap_start} - #{gap_end} from #{length(camera_recordings)} camera recordings"
        )

        state = %{state | gap_end: gap_end, cursor: gap_start, run: nil, runs: []}

        camera_recordings
        |> Enum.sort_by(& &1.start_date, DateTime)
        |> Enum.reduce(state, &backfill_recording(&2, &1))
        |> then(&Enum.reverse(finish_run(&1).runs))

      {:error, reason} ->
        Logger.error("[Backfiller] could not list camera recordings: #{inspect(reason)}")
        []
    end
  end

  # merge contiguous camera recordings and clamp them to the requested period
  defp camera_intervals(camera_recordings, start_date, end_date) do
    camera_recordings
    |> Enum.sort_by(& &1.start_date, DateTime)
    |> Enum.reduce([], fn
      %{start_date: rec_start, end_date: rec_end}, [{i_start, i_end} | rest] = acc ->
        if DateTime.diff(rec_start, i_end) <= @max_camera_gap,
          do: [{i_start, Enum.max([i_end, rec_end], DateTime)} | rest],
          else: [{rec_start, rec_end} | acc]

      %{start_date: rec_start, end_date: rec_end}, [] ->
        [{rec_start, rec_end}]
    end)
    |> Enum.reverse()
    |> Enum.map(fn {i_start, i_end} ->
      {Enum.max([i_start, start_date], DateTime), Enum.min([i_end, end_date], DateTime)}
    end)
    |> Enum.filter(fn {i_start, i_end} -> DateTime.before?(i_start, i_end) end)
  end

  # only query nvr runs in the period covered by the camera
  defp missing_in_nvr([], _device), do: []

  defp missing_in_nvr([{first_start, _end} | _rest] = camera_intervals, device) do
    {_start, last_end} = List.last(camera_intervals)
    intersect(camera_intervals, gaps(device, first_start, last_end, 0), [])
  end

  # intersection of two sorted lists of non overlapping intervals
  defp intersect([], _intervals, acc), do: Enum.reverse(acc)
  defp intersect(_intervals, [], acc), do: Enum.reverse(acc)

  defp intersect([{a_start, a_end} | a_rest] = a, [{b_start, b_end} | b_rest] = b, acc) do
    i_start = Enum.max([a_start, b_start], DateTime)
    i_end = Enum.min([a_end, b_end], DateTime)
    acc = if DateTime.before?(i_start, i_end), do: [{i_start, i_end} | acc], else: acc

    if DateTime.before?(a_end, b_end),
      do: intersect(a_rest, b, acc),
      else: intersect(a, b_rest, acc)
  end

  defp backfill_recording(state, %RemoteRecording{} = camera_rec) do
    if DateTime.after?(camera_rec.end_date, state.cursor) and
         DateTime.before?(camera_rec.start_date, state.gap_end) do
      dest = Path.join(state.tmp_dir, "backfill_#{camera_rec.id}.mp4")

      try do
        with :ok <- Devices.download_camera_recording(state.device, camera_rec, dest),
             {:ok, reader} <- open_reader(dest) do
          try do
            process_file(state, reader, camera_rec.start_date)
          after
            Reader.close(reader)
          end
        else
          {:error, reason} ->
            Logger.error(
              "[Backfiller] skip camera recording #{camera_rec.id}: #{inspect(reason)}"
            )

            state
        end
      after
        File.rm(dest)
      end
    else
      state
    end
  end

  defp open_reader(path) do
    Reader.new(path)
  rescue
    error -> {:error, error}
  end

  defp process_file(state, reader, file_start_date) do
    case Reader.track(reader, :video) do
      nil ->
        Logger.error("[Backfiller] camera recording has no video track")
        state

      track ->
        reader
        |> Reader.stream(tracks: [track.id])
        |> Enum.reduce_while(state, &process_sample(&2, reader, track, &1, file_start_date))
        |> close_chunk()
    end
  end

  defp process_sample(state, reader, track, metadata, file_start_date) do
    sample_date =
      DateTime.add(
        file_start_date,
        timescalify(metadata.dts, track.timescale, :microsecond),
        :microsecond
      )

    cond do
      not DateTime.before?(sample_date, state.gap_end) ->
        {:halt, state}

      # chunks start on a keyframe not already covered
      is_nil(state.chunk) and
          (not metadata.sync? or DateTime.before?(sample_date, state.cursor)) ->
        {:cont, state}

      true ->
        {:cont, handle_sample(state, reader, track, metadata, sample_date)}
    end
  end

  defp handle_sample(%{chunk: nil} = state, reader, track, metadata, sample_date) do
    state
    |> open_chunk(track, metadata.dts, sample_date)
    |> write_sample(reader, metadata)
  end

  defp handle_sample(%{chunk: chunk} = state, reader, track, metadata, sample_date) do
    duration = timescalify(metadata.dts - chunk.first_dts, chunk.timescale, :microsecond)

    if metadata.sync? and duration >= state.chunk_duration do
      state
      |> close_chunk()
      |> open_chunk(track, metadata.dts, sample_date)
      |> write_sample(reader, metadata)
    else
      write_sample(state, reader, metadata)
    end
  end

  defp open_chunk(state, track, first_dts, start_date) do
    path = Recordings.recording_path(state.device, :high, %{start_date: start_date})
    File.mkdir_p!(Path.dirname(path))

    writer =
      path
      |> Writer.new!(fast_start: true)
      |> Writer.write_header()
      |> Writer.add_track(%Track{
        type: :video,
        media: track.media,
        media_tag: track.media_tag,
        width: track.width,
        height: track.height,
        timescale: track.timescale,
        priv_data: track.priv_data
      })

    chunk = %{
      writer: writer,
      path: path,
      track_id: writer |> Writer.tracks() |> hd() |> Map.fetch!(:id),
      timescale: track.timescale,
      start_date: start_date,
      first_dts: first_dts,
      end_dts: first_dts
    }

    %{state | chunk: chunk}
  end

  defp write_sample(%{chunk: chunk} = state, reader, metadata) do
    sample = Reader.read_sample(reader, metadata)

    sample = %{
      sample
      | track_id: chunk.track_id,
        dts: sample.dts - chunk.first_dts,
        pts: sample.pts - chunk.first_dts
    }

    chunk = %{
      chunk
      | writer: Writer.write_sample(chunk.writer, sample),
        end_dts: metadata.dts + metadata.duration
    }

    %{state | chunk: chunk}
  end

  defp close_chunk(%{chunk: nil} = state), do: state

  defp close_chunk(%{chunk: chunk} = state) do
    duration = timescalify(chunk.end_dts - chunk.first_dts, chunk.timescale, :microsecond)
    end_date = DateTime.add(chunk.start_date, duration, :microsecond)
    {state, run} = run_for_chunk(state, chunk.start_date, end_date)

    recording = %{
      device_id: state.device.id,
      stream: :high,
      start_date: chunk.start_date,
      end_date: end_date,
      path: chunk.path
    }

    # save to db first, the run id is needed in the file metadata
    case Recordings.create(state.device, run, recording, false) do
      {:ok, _recording, run} ->
        :ok = Writer.write_trailer(chunk.writer, uuid: [metadata_box(run, chunk.start_date)])
        %{state | chunk: nil, run: run, cursor: end_date}

      {:error, reason} ->
        Logger.error(
          "[Backfiller] could not save recording #{inspect(recording)}: #{inspect(reason)}"
        )

        # files without a run id must not be kept
        :ok = Writer.write_trailer(chunk.writer)
        File.rm(chunk.path)
        finish_run(%{state | chunk: nil})
    end
  end

  defp run_for_chunk(%{run: nil} = state, start_date, end_date) do
    run = %Run{
      start_date: start_date,
      end_date: end_date,
      device_id: state.device.id,
      stream: :high,
      active: false,
      disk_serial: ExNVR.Disk.serial(state.device.storage_config.address)
    }

    {state, run}
  end

  defp run_for_chunk(%{run: run} = state, start_date, end_date) do
    if DateTime.diff(start_date, run.end_date, :microsecond) <= @max_run_gap_us,
      do: {state, %{run | end_date: end_date}},
      else: state |> finish_run() |> run_for_chunk(start_date, end_date)
  end

  defp finish_run(%{run: nil} = state), do: state
  defp finish_run(%{run: run} = state), do: %{state | run: nil, runs: [run | state.runs]}

  defp metadata_box(%Run{id: run_id}, start_date) do
    metadata = %{run_id: run_id, start_date: DateTime.to_unix(start_date, :millisecond)}
    Box.UUID.new(Storage.metadata_uuid(), Jason.encode!(metadata))
  end
end
