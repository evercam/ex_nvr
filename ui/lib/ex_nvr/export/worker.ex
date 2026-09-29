defmodule ExNVR.Export.Worker do
  @moduledoc """
  Exports a device's footage to sequential MP4 files on the filesystem.

  With a remote (S3) destination, `dest_dir` is a staging directory: each
  finalized file is uploaded in the background and deleted locally once
  uploaded. The job only completes after every file (and the job manifest)
  has been uploaded.
  """

  use GenServer

  require Logger

  alias ExMP4.{Helper, Writer}
  alias ExNVR.Export.{Manifest, S3}
  alias ExNVR.Recordings.Concatenater
  alias ExNVR.{RemoteStorage, RemoteStorages}

  # In :hourly split mode, a recording gap longer than this starts a new file.
  @max_gap_seconds 300
  # Generation pauses once this many finalized files are waiting for upload,
  # bounding the staging directory to about that many files.
  @max_pending_uploads 2
  @max_upload_attempts 6

  defstruct [
    :device,
    :stream,
    :dest_dir,
    :manifest,
    :cat,
    :track,
    :current_file,
    :remote_opts,
    :upload,
    :retry_timer,
    upload_attempts: 0,
    # :generating - producing files; :backlogged - generation held until an
    # upload frees a slot; :draining - all files produced, finishing uploads.
    phase: :generating,
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
         :ok <- check_identity(manifest, device, stream),
         {:ok, remote_opts} <- remote_opts(manifest.destination) do
      state = %__MODULE__{
        device: device,
        stream: stream,
        dest_dir: dest_dir,
        manifest: manifest,
        remote_opts: remote_opts,
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
    # Files left pending by a previous (paused/crashed) run are re-queued.
    state = maybe_start_upload(state)

    case Concatenater.new(state.device, state.stream, state.manifest.cursor, annexb: false) do
      {:ok, _offset, cat} ->
        [track] = Concatenater.tracks(cat)
        send(self(), :export_tick)
        {:noreply, %{state | cat: cat, track: track}}

      {:error, :end_of_stream} when state.manifest.files == [] ->
        {:stop, {:shutdown, :no_recordings}, mark_failed(state, "no_recordings")}

      {:error, :end_of_stream} ->
        drain(state)

      {:error, :codec_changed} ->
        {:stop, {:shutdown, :codec_changed}, mark_failed(state, "codec_changed")}
    end
  end

  @impl true
  def handle_info(:export_tick, state) do
    if upload_backlog?(state),
      do: {:noreply, %{state | phase: :backlogged}},
      else: do_export_tick(state)
  end

  def handle_info(:retry_upload, state) do
    {:noreply, maybe_start_upload(%{state | retry_timer: nil})}
  end

  def handle_info({ref, result}, %{upload: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])
    handle_upload_result(state, result)
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{upload: %{ref: ref}} = state) do
    handle_upload_result(state, {:error, {:upload_crashed, reason}})
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp do_export_tick(state) do
    case process_gop(state) do
      {:yield, state} ->
        if state.notify,
          do: send(state.notify, {:export_tick, state.dest_dir, length(state.manifest.files)})

        if state.tick_delay > 0, do: Process.sleep(state.tick_delay)
        send(self(), :export_tick)
        {:noreply, maybe_start_upload(state)}

      {:done, state, cursor} ->
        state |> finalize_current_file(cursor) |> drain()

      {:stopped, state, cursor} ->
        state = state |> finalize_current_file(cursor) |> cancel_upload() |> mark_paused()
        {:stop, :normal, reply_to_stop(state)}

      {:error, reason, state} ->
        state =
          state
          |> finalize_current_file(last_sample_end(state))
          |> cancel_upload()
          |> mark_failed(to_string(reason))

        {:stop, {:shutdown, reason}, reply_to_stop(state)}
    end
  end

  @impl true
  # While generating, the stop is honoured on the next keyframe so the file
  # being written is finalized cleanly. Otherwise (waiting on uploads) there
  # is no open file and we can pause right away.
  def handle_call(:stop, from, %{phase: :generating} = state),
    do: {:noreply, %{state | stop_requested?: true, stop_from: from}}

  def handle_call(:stop, _from, state) do
    state = state |> cancel_upload() |> mark_paused()
    {:stop, :normal, :ok, state}
  end

  def handle_call(:progress, _from, state), do: {:reply, {:ok, build_progress(state)}, state}

  # Called when a callback raises. Every planned stop records its own status
  # first, so a manifest still `:running` here means the job crashed.
  @impl true
  def terminate(reason, %{manifest: %{status: :running}} = state) do
    state = cancel_upload(state)
    Logger.error("[Export] #{state.dest_dir} crashed: #{inspect(reason)}")

    try do
      mark_failed(state, crash_message(reason))
    rescue
      # e.g. the USB drive holding the export was unplugged
      error -> Logger.error("[Export] could not record the crash: #{Exception.message(error)}")
    end

    :ok
  end

  def terminate(_reason, state) do
    cancel_upload(state)
    :ok
  end

  @doc false
  @spec crash_message(term()) :: String.t()
  def crash_message({exception, _stacktrace}) when is_exception(exception) do
    message = Exception.message(exception)

    if message =~ ":enoent" or match?(%File.Error{reason: :enoent}, exception),
      do:
        "a recording was deleted while it was being exported (the disk is probably full and " <>
          "old footage is being removed); retry to continue from the last completed file",
      else: "crashed: " <> String.slice(message, 0, 200)
  end

  def crash_message(reason), do: "crashed: " <> String.slice(inspect(reason), 0, 200)

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

  defp rotate?(%{current_file: cf, manifest: %{split: :hourly}}, ts) do
    DateTime.compare(ts, cf.rotate_at) != :lt or
      DateTime.diff(ts, cf.last_sample_end, :second) > @max_gap_seconds
  end

  defp rotate?(%{current_file: cf, manifest: m}, ts) do
    (m.max_duration && DateTime.diff(ts, cf.start_date, :second) >= m.max_duration) ||
      (m.max_file_size && cf.bytes >= m.max_file_size) || false
  end

  @doc false
  @spec next_hour_boundary(DateTime.t(), String.t()) :: DateTime.t()
  def next_hour_boundary(ts, timezone) do
    local = DateTime.shift_zone!(ts, timezone)
    hour_start = %{local | minute: 0, second: 0, microsecond: {0, 6}}

    hour_start
    |> DateTime.add(3600, :second)
    |> DateTime.shift_zone!("Etc/UTC")
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
      rotate_at: rotate_at(state.manifest, ts),
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

  defp rotate_at(%{split: :hourly, timezone: timezone}, ts), do: next_hour_boundary(ts, timezone)
  defp rotate_at(_manifest, _ts), do: nil

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

    entry =
      %{
        filename: cf.filename,
        start_date: cf.start_date,
        end_date: file_end(state, cursor),
        size: size
      }
      |> put_remote_key(state.manifest)

    manifest =
      %{state.manifest | files: state.manifest.files ++ [entry], cursor: cursor}
      |> Manifest.save!(state.dest_dir)

    %{state | manifest: manifest, current_file: nil}
  end

  # The cursor is where the next file starts; across a recording gap that is
  # later than the last frame of this file.
  defp file_end(%{manifest: %{split: :hourly}, current_file: cf}, cursor),
    do: Enum.min([cursor, cf.last_sample_end], DateTime)

  defp file_end(_state, cursor), do: cursor

  defp put_remote_key(entry, %{destination: nil}), do: entry

  defp put_remote_key(entry, manifest) do
    key = S3.object_key(manifest.destination, entry.start_date, manifest.timezone)
    Map.merge(entry, %{key: unique_key(key, manifest.files), upload_status: :pending})
  end

  # Two files of one job can map to the same key when the local hour repeats
  # (DST fall-back); suffix the later one instead of letting it be skipped.
  defp unique_key(key, files, n \\ 1) do
    candidate = if n == 1, do: key, else: String.replace_suffix(key, ".mp4", "_#{n}.mp4")

    if Enum.any?(files, &(&1[:key] == candidate)),
      do: unique_key(key, files, n + 1),
      else: candidate
  end

  ## Remote upload

  defp remote_opts(nil), do: {:ok, nil}

  defp remote_opts(%{type: :s3, remote_storage_id: id}) do
    case RemoteStorages.get(id) do
      %RemoteStorage{type: :s3} = remote_storage ->
        {:ok, RemoteStorage.build_opts(remote_storage)}

      _other ->
        {:error, :remote_storage_not_found}
    end
  end

  defp upload_backlog?(%{remote_opts: nil}), do: false

  defp upload_backlog?(state),
    do: length(pending_uploads(state.manifest)) >= @max_pending_uploads

  defp pending_uploads(manifest) do
    manifest.files
    |> Enum.with_index()
    |> Enum.filter(fn {file, _index} -> file[:upload_status] == :pending end)
  end

  defp drain(%{remote_opts: nil} = state),
    do: {:stop, :normal, state |> mark_completed() |> reply_to_stop()}

  # A stop requested during the last GOP is honoured by pausing; resuming
  # goes straight back to draining.
  defp drain(%{stop_from: from} = state) when from != nil do
    state = state |> cancel_upload() |> mark_paused()
    {:stop, :normal, reply_to_stop(state)}
  end

  defp drain(state), do: {:noreply, maybe_start_upload(%{state | phase: :draining})}

  defp maybe_start_upload(%{remote_opts: nil} = state), do: state
  defp maybe_start_upload(%{upload: upload} = state) when upload != nil, do: state
  defp maybe_start_upload(%{retry_timer: timer} = state) when timer != nil, do: state

  defp maybe_start_upload(state) do
    case {pending_uploads(state.manifest), state.phase} do
      {[{file, index} | _rest], _phase} ->
        path = Path.join(state.dest_dir, file.filename)

        run_upload(state, {:file, index}, fn ->
          upload_staged_file(path, file.key, state.remote_opts)
        end)

      {[], :draining} ->
        manifest = %{state.manifest | status: :completed}
        key = S3.manifest_key(manifest.destination)

        run_upload(state, :manifest, fn ->
          S3.put_json(key, remote_manifest(manifest), state.remote_opts)
        end)

      {[], _phase} ->
        state
    end
  end

  defp run_upload(state, item, fun) do
    task = Task.Supervisor.async_nolink(ExNVR.TaskSupervisor, fun)
    %{state | upload: %{ref: task.ref, task: task, item: item}}
  end

  # The staged file is gone only if a previous run uploaded it and was killed
  # before recording that in the manifest.
  defp upload_staged_file(path, key, opts) do
    if File.exists?(path),
      do: S3.upload_file(path, key, opts),
      else: {:error, :staged_file_missing}
  end

  defp handle_upload_result(%{upload: %{item: :manifest}} = state, :ok) do
    log_upload_flags(state.manifest)
    state = %{state | upload: nil} |> mark_completed()
    {:stop, :normal, reply_to_stop(state)}
  end

  defp handle_upload_result(%{upload: %{item: {:file, index}}} = state, {:ok, upload_status}) do
    file = Enum.at(state.manifest.files, index)

    # Record the upload before deleting the staged copy, so a crash in between
    # never leaves a pending entry without its file.
    files = List.replace_at(state.manifest.files, index, put_upload_status(file, upload_status))
    manifest = Manifest.save!(%{state.manifest | files: files}, state.dest_dir)
    File.rm(Path.join(state.dest_dir, file.filename))
    state = %{state | manifest: manifest, upload: nil, upload_attempts: 0}

    state =
      if state.phase == :backlogged and not upload_backlog?(state) do
        send(self(), :export_tick)
        %{state | phase: :generating}
      else
        state
      end

    {:noreply, maybe_start_upload(state)}
  end

  defp handle_upload_result(state, {:error, reason}) do
    attempts = state.upload_attempts + 1
    target = upload_target(state)
    state = %{state | upload: nil, upload_attempts: attempts}

    if attempts >= @max_upload_attempts or reason == :staged_file_missing or
         S3.permanent_error?(reason) do
      Logger.error("[S3 export] upload of #{target} failed: #{inspect(reason)}")

      state =
        state
        |> finalize_current_file(last_sample_end(state))
        |> mark_failed("upload failed: #{S3.describe_error(reason)}")

      {:stop, {:shutdown, {:upload_failed, reason}}, reply_to_stop(state)}
    else
      delay = retry_delay(attempts)

      Logger.warning(
        "[S3 export] upload of #{target} failed (attempt #{attempts}), retrying in #{delay}ms: #{S3.describe_error(reason)}"
      )

      {:noreply, %{state | retry_timer: Process.send_after(self(), :retry_upload, delay)}}
    end
  end

  defp put_upload_status(file, {:overwritten, previous_size}),
    do: Map.merge(file, %{upload_status: :overwritten, previous_size: previous_size})

  defp put_upload_status(file, upload_status), do: %{file | upload_status: upload_status}

  defp log_upload_flags(manifest) do
    %{skipped: skipped, overwritten: overwritten} = Manifest.upload_flags(manifest)

    if skipped != [] or overwritten != [] do
      Logger.warning("""
      [S3 export] #{manifest.destination.job_id} completed with #{length(skipped)} skipped \
      and #{length(overwritten)} overwritten file(s)
      skipped (already in bucket): #{Enum.map_join(skipped, ", ", & &1.key)}
      overwritten: #{Enum.map_join(overwritten, ", ", &"#{&1.key} (was #{&1.previous_size} bytes)")}
      """)
    end
  end

  defp upload_target(%{upload: %{item: :manifest}, manifest: m}),
    do: S3.manifest_key(m.destination)

  defp upload_target(%{upload: %{item: {:file, index}}, manifest: m}),
    do: Enum.at(m.files, index).key

  defp retry_delay(attempts) do
    base = Application.get_env(:ex_nvr, :export_upload_retry_base_ms, 10_000)
    base * Integer.pow(2, attempts - 1)
  end

  defp cancel_upload(%{upload: nil} = state), do: cancel_retry(state)

  defp cancel_upload(%{upload: %{task: task}} = state) do
    Task.shutdown(task, :brutal_kill)
    cancel_retry(%{state | upload: nil})
  end

  defp cancel_retry(%{retry_timer: nil} = state), do: state

  defp cancel_retry(%{retry_timer: timer} = state) do
    Process.cancel_timer(timer)
    %{state | retry_timer: nil}
  end

  defp remote_manifest(manifest) do
    flags = Manifest.upload_flags(manifest)

    %{
      job_id: manifest.destination.job_id,
      kit_id: manifest.destination.kit_id,
      camera_id: manifest.destination.camera_id,
      device_id: manifest.device_id,
      stream: manifest.stream,
      timezone: manifest.timezone,
      start_date: manifest.start_date,
      end_date: manifest.end_date,
      completed_at: DateTime.utc_now(),
      files:
        Enum.map(manifest.files, fn file ->
          Map.take(file, [:key, :start_date, :end_date, :size, :upload_status, :previous_size])
        end),
      # Flagged separately so they stand out when reviewing the export.
      skipped: Enum.map(flags.skipped, & &1.key),
      overwritten:
        Enum.map(
          flags.overwritten,
          &%{key: &1.key, size: &1.size, previous_size: &1.previous_size}
        )
    }
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
          max_file_size: args[:max_file_size],
          split: args[:split],
          timezone: args[:device].timezone,
          destination: args[:destination]
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
      files_uploaded: Manifest.uploaded_count(m),
      remote?: m.destination != nil,
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
