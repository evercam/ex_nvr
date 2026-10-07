defmodule ExNVR.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """

  alias ExNVR.Model.{Recording, Run}
  alias ExNVR.Recordings.Reindexer

  @app :ex_nvr

  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _fun_return, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load_app()

    {:ok, _fun_return, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  @doc """
  Rebuild the runs and recordings of a device from the mp4 files stored in `path`.

  See `ExNVR.Recordings.Reindexer.scan/3` for the options.
  """
  @spec reindex_recordings(Path.t(), binary(), Reindexer.scan_opts()) ::
          {[Run.t()], [Recording.t()]}
  def reindex_recordings(path, device_id, opts \\ []) do
    load_app()

    # needed by ExNVR.Disk, the app is not started in release eval
    if is_nil(Process.whereis(ExNVR.TaskSupervisor)) do
      {:ok, _pid} = Task.Supervisor.start_link(name: ExNVR.TaskSupervisor)
    end

    if opts[:save] do
      {:ok, result, _apps} =
        Ecto.Migrator.with_repo(ExNVR.Repo, fn _repo -> Reindexer.scan(path, device_id, opts) end)

      result
    else
      Reindexer.scan(path, device_id, opts)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
