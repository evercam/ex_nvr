defmodule ExNVR.Export.Worker do
  @moduledoc "Exports a device's footage to sequential MP4 files on the filesystem."

  use GenServer

  require Logger

  alias ExMP4.{Helper, Writer}
  alias ExNVR.Export.Manifest
  alias ExNVR.Recordings.Concatenater

  defstruct [
    :device,
    :stream,
    :dest_dir,
    :manifest,
    :cat,
    :track,
    :current_file,
    stop_requested?: false,
    stop_from: nil,
    tick_delay: 0,
    notify: nil
  ]

  @spec via_tuple(Path.t()) :: {:via, Registry, {ExNVR.Export.Registry, Path.t()}}
  def via_tuple(dest_dir), do: {:via, Registry, {ExNVR.Export.Registry, dest_dir}}

  def child_spec(args) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, [args]}, restart: :temporary}
  end

  def start_link(args) do
    dest_dir = Keyword.fetch!(args, :dest_dir)
    GenServer.start_link(__MODULE__, args, name: via_tuple(dest_dir))
  end

  @impl true
  def init(args) do
    device = Keyword.fetch!(args, :device)
    stream = Keyword.fetch!(args, :stream)
    dest_dir = Keyword.fetch!(args, :dest_dir)

    with :ok <- validate_opts(args),
         {:ok, manifest} <- open_or_create_manifest(args, dest_dir),
         :ok <- check_identity(manifest, device, stream) do
      state = %__MODULE__{
        device: device,
        stream: stream,
        dest_dir: dest_dir,
        manifest: manifest,
        tick_delay: args[:tick_delay] || 0,
        notify: args[:notify]
      }

      {:ok, state, {:continue, :open_stream}}
    else
      {:error, reason} -> {:stop, {:shutdown, reason}}
    end
  end

  @impl true
  def handle_continue(:open_stream, state) do
    case Concatenater.new(state.device, state.stream, state.manifest.cursor, annexb: false) do
      {:ok, _offset, cat} ->
        [track] = Concatenater.tracks(cat)
        send(self(), :export_tick)
        {:noreply, %{state | cat: cat, track: track}}

      {:error, :end_of_stream} when state.manifest.files == [] ->
        {:stop, {:shutdown, :no_recordings}, mark_failed(state, "no_recordings")}

      {:error, :end_of_stream} ->
        {:stop, :normal, mark_completed(state)}

      {:error, :codec_changed} ->
        {:stop, {:shutdown, :codec_changed}, mark_failed(state, "codec_changed")}
    end
  end

  @impl true
  def handle_info(:export_tick, state) do
    case process_gop(state) do
      {:yield, state} ->
        if state.notify,
          do: send(state.notify, {:export_tick, state.dest_dir, length(state.manifest.files)})

        if state.tick_delay > 0, do: Process.sleep(state.tick_delay)
        send(self(), :export_tick)
        {:noreply, state}

      {:done, state, cursor} ->
        state = state |> finalize_current_file(cursor) |> mark_completed()
        {:stop, :normal, reply_to_stop(state)}

      {:stopped, state, cursor} ->
        state = state |> finalize_current_file(cursor) |> mark_paused()
        {:stop, :normal, reply_to_stop(state)}

      {:error, reason, state} ->
        state =
          state
          |> finalize_current_file(last_sample_end(state))
          |> mark_failed(to_string(reason))

        {:stop, {:shutdown, reason}, reply_to_stop(state)}
    end
  end

  @impl true
  def handle_call(:stop, from, state),
    do: {:noreply, %{state | stop_requested?: true, stop_from: from}}

  def handle_call(:progress, _from, state), do: {:reply, {:ok, build_progress(state)}, state}

  defp reply_to_stop(%{stop_from: nil} = state), do: state

  defp reply_to_stop(%{stop_from: from} = state) do
    GenServer.reply(from, :ok)
    %{state | stop_from: nil}
  end

  # Rotate/stop/finalize decisions happen only on sync (keyframe) samples,
  # so every finalized file starts and ends cleanly on a GOP boundary.
  defp process_gop(state) do
    case Concatenater.next_sample(state.cat, state.track.id) do
      {:error, :end_of_stream} -> {:done, state, last_sample_end(state)}
      {:error, :codec_changed} -> {:error, :codec_changed, state}
      {:ok, {sample, ts}, cat} -> handle_sample(%{state | cat: cat}, sample, ts)
    end
  end

  defp handle_sample(state, sample, ts) do
    cond do
      DateTime.compare(ts, state.manifest.end_date) != :lt ->
        {:done, state, state.manifest.end_date}

      sample.sync? ->
        handle_sync_sample(state, sample, ts)

      true ->
        process_gop(write_sample(state, sample, ts))
    end
  end

  defp handle_sync_sample(%{stop_requested?: true} = state, _sample, ts),
    do: {:stopped, state, ts}

  defp handle_sync_sample(%{current_file: nil} = state, sample, ts) do
    state |> open_new_file(ts) |> write_sample(sample, ts) |> then(&{:yield, &1})
  end

  defp handle_sync_sample(state, sample, ts) do
    if rotate?(state, ts) do
      state
      |> finalize_current_file(ts)
      |> open_new_file(ts)
      |> write_sample(sample, ts)
      |> then(&{:yield, &1})
    else
      {:yield, write_sample(state, sample, ts)}
    end
  end

  defp rotate?(%{current_file: cf, manifest: m}, ts) do
    (m.max_duration && DateTime.diff(ts, cf.start_date, :second) >= m.max_duration) ||
      (m.max_file_size && cf.bytes >= m.max_file_size) || false
  end

  defp open_new_file(state, ts) do
    index = length(state.manifest.files)
    filename = "export_" <> String.pad_leading(Integer.to_string(index), 5, "0") <> ".mp4"
    path = Path.join(state.dest_dir, filename)

    # ExMP4.Writer opens in exclusive mode; a crashed prior attempt may have
    # left a stray, trailer-less file at this deterministic path.
    File.rm(path)

    writer =
      Writer.new!(path)
      |> Writer.add_track(state.track)
      |> Writer.write_header()

    current_file = %{
      writer: writer,
      path: path,
      filename: filename,
      start_date: ts,
      last_sample_end: ts,
      bytes: 0
    }

    %{state | current_file: current_file}
  end

  defp write_sample(state, sample, ts) do
    writer = Writer.write_sample(state.current_file.writer, sample)
    bytes = state.current_file.bytes + IO.iodata_length(sample.payload)

    duration_us = Helper.timescalify(sample.duration, state.track.timescale, :microsecond)
    end_ts = DateTime.add(ts, duration_us, :microsecond)

    current_file = %{state.current_file | writer: writer, bytes: bytes, last_sample_end: end_ts}
    %{state | current_file: current_file}
  end

  defp last_sample_end(%{current_file: nil, manifest: manifest}), do: manifest.cursor
  defp last_sample_end(%{current_file: cf}), do: cf.last_sample_end

  # Only appended to the manifest (advancing `cursor`) once write_trailer/1
  # succeeds, so a file is never referenced until it's fully valid.
  defp finalize_current_file(%{current_file: nil} = state, cursor) do
    %{state | manifest: %{state.manifest | cursor: cursor}}
  end

  defp finalize_current_file(%{current_file: cf} = state, cursor) do
    :ok = Writer.write_trailer(cf.writer)
    size = File.stat!(cf.path).size

    entry = %{filename: cf.filename, start_date: cf.start_date, end_date: cursor, size: size}

    manifest =
      %{state.manifest | files: state.manifest.files ++ [entry], cursor: cursor}
      |> Manifest.save!(state.dest_dir)

    %{state | manifest: manifest, current_file: nil}
  end

  defp mark_completed(state), do: save_manifest_status(state, :completed, nil)
  defp mark_paused(state), do: save_manifest_status(state, :paused, nil)
  defp mark_failed(state, reason), do: save_manifest_status(state, :failed, reason)

  defp save_manifest_status(state, status, error) do
    manifest = Manifest.save!(%{state.manifest | status: status, error: error}, state.dest_dir)
    %{state | manifest: manifest}
  end

  defp validate_opts(args) do
    cond do
      args[:max_duration] not in [nil, false] and args[:max_duration] <= 0 ->
        {:error, :invalid_max_duration}

      args[:max_file_size] not in [nil, false] and args[:max_file_size] <= 0 ->
        {:error, :invalid_max_file_size}

      true ->
        :ok
    end
  end

  defp open_or_create_manifest(args, dest_dir) do
    case Manifest.load(dest_dir) do
      {:ok, %{status: status} = manifest} when status in [:running, :paused] ->
        {:ok, manifest}

      {:ok, %{status: :completed} = manifest} ->
        {:error, {:already_completed, manifest}}

      {:ok, %{status: :failed} = manifest} ->
        maybe_force_restart(manifest, args, dest_dir)

      {:error, :not_found} ->
        File.mkdir_p!(dest_dir)

        params = %{
          device_id: args[:device].id,
          stream: args[:stream],
          start_date: args[:start_date],
          end_date: args[:end_date],
          max_duration: args[:max_duration],
          max_file_size: args[:max_file_size]
        }

        {:ok, Manifest.new(params) |> Manifest.save!(dest_dir)}

      {:error, :invalid} ->
        {:error, :invalid_manifest}
    end
  end

  defp maybe_force_restart(manifest, args, dest_dir) do
    if args[:force] do
      {:ok, Manifest.save!(%{manifest | status: :running, error: nil}, dest_dir)}
    else
      {:error, {:job_failed, manifest}}
    end
  end

  defp check_identity(%{device_id: device_id, stream: stream}, %{id: device_id}, stream), do: :ok
  defp check_identity(_manifest, _device, _stream), do: {:error, :device_mismatch}

  defp build_progress(state) do
    m = state.manifest
    total = DateTime.diff(m.end_date, m.start_date, :microsecond)
    done = DateTime.diff(m.cursor, m.start_date, :microsecond)
    percentage = if total > 0, do: (done / total * 100) |> min(100.0) |> max(0.0), else: 100.0

    %{
      status: m.status,
      percentage: Float.round(percentage * 1.0, 2),
      cursor: m.cursor,
      files_completed: length(m.files),
      files: m.files,
      error: m.error,
      current_file: current_file_progress(state.current_file)
    }
  end

  defp current_file_progress(nil), do: nil

  defp current_file_progress(cf) do
    %{
      filename: cf.filename,
      start_date: cf.start_date,
      elapsed_seconds: DateTime.diff(cf.last_sample_end, cf.start_date),
      bytes: cf.bytes
    }
  end
end
