defmodule ExNVR.Export do
  @moduledoc "Export device footage to sequential MP4 files. The destination directory is the job's identity."

  alias ExNVR.Export.{Manifest, Worker}
  alias ExNVR.Model.Device
  alias ExNVR.Recordings

  @type export_opts :: [
          max_duration: pos_integer(),
          max_file_size: pos_integer(),
          force: boolean()
        ]

  @type progress :: %{
          status: Manifest.status(),
          percentage: float(),
          cursor: DateTime.t(),
          files_completed: non_neg_integer(),
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
          force: Keyword.get(opts, :force, false)
        ]

        case DynamicSupervisor.start_child(ExNVR.Export.Supervisor, {Worker, args}) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:shutdown, reason}} -> {:error, reason}
          {:error, reason} -> {:error, reason}
        end
    end
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
      {:ok, progress_from_manifest(manifest)}
    end
  end

  defp progress_from_manifest(manifest) do
    %{
      status: manifest.status,
      percentage: percentage(manifest),
      cursor: manifest.cursor,
      files_completed: length(manifest.files),
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
