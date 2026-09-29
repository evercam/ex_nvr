defmodule ExNVR.Export do
  @moduledoc "Export device footage to sequential MP4 files. The destination directory is the job's identity."

  import Ecto.Query

  alias ExNVR.Export.{Job, Manifest, Worker}
  alias ExNVR.Model.Device
  alias ExNVR.{Recordings, Repo}

  @type export_opts :: [
          max_duration: pos_integer(),
          max_file_size: pos_integer(),
          split: Manifest.split(),
          destination: Manifest.destination(),
          force: boolean()
        ]

  @type progress :: %{
          status: Manifest.status(),
          percentage: float(),
          cursor: DateTime.t(),
          files_completed: non_neg_integer(),
          files_uploaded: non_neg_integer(),
          remote?: boolean(),
          files: [Manifest.file_entry()],
          current_file: current_file() | nil,
          error: String.t() | nil
        }

  @type current_file :: %{
          filename: String.t(),
          start_date: DateTime.t(),
          elapsed_seconds: non_neg_integer(),
          bytes: non_neg_integer()
        }

  @spec start(
          Device.t(),
          Recordings.stream_type(),
          DateTime.t(),
          DateTime.t(),
          Path.t(),
          export_opts()
        ) ::
          {:ok, pid()}
          | {:error, :device_mismatch}
          | {:error, {:already_completed, Manifest.t()}}
          | {:error, {:job_failed, Manifest.t()}}
          | {:error, term()}
  def start(device, stream, start_date, end_date, dest_dir, opts \\ []) do
    dest_dir = Path.expand(dest_dir)

    case Registry.lookup(ExNVR.Export.Registry, dest_dir) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        args = [
          device: device,
          stream: stream,
          start_date: start_date,
          end_date: end_date,
          dest_dir: dest_dir,
          max_duration: opts[:max_duration],
          max_file_size: opts[:max_file_size],
          split: Keyword.get(opts, :split, :duration),
          destination: opts[:destination],
          force: Keyword.get(opts, :force, false)
        ]

        case DynamicSupervisor.start_child(ExNVR.Export.Supervisor, {Worker, args}) do
          {:ok, pid} ->
            track(dest_dir, device, opts[:destination])
            {:ok, pid}

          {:error, {:shutdown, reason}} ->
            {:error, reason}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @type recent_job :: %{
          dest_dir: Path.t(),
          device_id: binary(),
          kind: :usb | :s3,
          updated_at: DateTime.t(),
          manifest: Manifest.t() | nil,
          progress: progress() | nil
        }

  @doc """
  Most recently started or resumed jobs, newest first. `manifest` and
  `progress` are nil when the job's directory is no longer reachable (e.g. the
  USB drive was unplugged or the folder deleted).
  """
  @spec list_recent(pos_integer()) :: [recent_job()]
  def list_recent(limit \\ 10) do
    Job
    |> order_by(desc: :updated_at, desc: :id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.map(fn job ->
      {manifest, progress} =
        case Manifest.load(job.dest_dir) do
          {:ok, manifest} ->
            {:ok, progress} = progress(job.dest_dir)
            {manifest, progress}

          {:error, _reason} ->
            {nil, nil}
        end

      job
      |> Map.take([:dest_dir, :device_id, :kind, :updated_at])
      |> Map.merge(%{manifest: manifest, progress: progress})
    end)
  end

  defp track(dest_dir, device, destination) do
    kind = if destination, do: :s3, else: :usb
    now = DateTime.utc_now()

    Repo.insert!(
      %Job{
        dest_dir: dest_dir,
        device_id: device.id,
        kind: kind,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [set: [updated_at: now]],
      conflict_target: :dest_dir
    )
  end

  @spec stop(Path.t()) :: :ok | {:error, :not_found}
  def stop(dest_dir) do
    case Registry.lookup(ExNVR.Export.Registry, Path.expand(dest_dir)) do
      [{pid, _}] ->
        # The worker may finish and terminate between the lookup and the
        # call (jobs can complete near-instantly); treat that race as :ok.
        try do
          GenServer.call(pid, :stop, :infinity)
        catch
          :exit, _ -> :ok
        end

      [] ->
        {:error, :not_found}
    end
  end

  @spec progress(Path.t()) :: {:ok, progress()} | {:error, :not_found}
  def progress(dest_dir) do
    dest_dir = Path.expand(dest_dir)

    case Registry.lookup(ExNVR.Export.Registry, dest_dir) do
      [{pid, _}] ->
        try do
          GenServer.call(pid, :progress)
        catch
          :exit, _ -> progress_from_disk(dest_dir)
        end

      [] ->
        progress_from_disk(dest_dir)
    end
  end

  defp progress_from_disk(dest_dir) do
    with {:ok, manifest} <- Manifest.load(dest_dir) do
      {:ok, manifest |> interrupted() |> progress_from_manifest()}
    end
  end

  # "running" on disk with no worker: the node restarted or the worker was
  # killed mid-job. It can be resumed like a paused job.
  defp interrupted(%{status: :running} = manifest) do
    %{
      manifest
      | status: :paused,
        error: "interrupted: the export stopped unexpectedly (e.g. a restart), resume to continue"
    }
  end

  defp interrupted(manifest), do: manifest

  defp progress_from_manifest(manifest) do
    %{
      status: manifest.status,
      percentage: percentage(manifest),
      cursor: manifest.cursor,
      files_completed: length(manifest.files),
      files_uploaded: Manifest.uploaded_count(manifest),
      remote?: manifest.destination != nil,
      files: manifest.files,
      error: manifest.error,
      current_file: nil
    }
  end

  defp percentage(%{status: :completed}), do: 100.0

  defp percentage(manifest) do
    total = DateTime.diff(manifest.end_date, manifest.start_date, :microsecond)
    done = DateTime.diff(manifest.cursor, manifest.start_date, :microsecond)

    if total > 0,
      do: (done / total * 100) |> min(100.0) |> max(0.0) |> Float.round(2),
      else: 100.0
  end
end
