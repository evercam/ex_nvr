defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """

  alias Ecto.Multi
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.Repo

  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec create(Run.t(), map()) :: {:ok, Recording.t(), Run.t()} | error()
  def create(%Run{} = run, %{path: path} = params) do
    params = if is_struct(params), do: Map.from_struct(params), else: params

    with :ok <- File.cp(path, recording_path(params)) do
      recording_changeset =
        params
        |> Map.put(:filename, recording_path(params) |> Path.basename())
        |> Recording.changeset()

      Multi.new()
      |> Multi.insert(:recording, recording_changeset)
      |> Multi.insert(:run, run, on_conflict: :replace_all)
      |> Repo.transaction()
      |> case do
        {:ok, %{recording: recording, run: run}} -> {:ok, recording, run}
        {:error, _, changeset, _} -> {:error, changeset}
      end
    end
  end

  @spec get_recordings_after(DateTime.t()) :: [Recording.t()]
  def get_recordings_after(date, opts \\ []) do
    date
    |> Recording.after_date(opts)
    |> Repo.all()
  end

  @spec get_blob(Device.t(), binary()) :: binary() | nil
  def get_blob(%Device{id: id}, filename) do
    with %Recording{} = rec <- Repo.get_by(Recording, %{device_id: id, filename: filename}) do
      File.read!(recording_path(rec))
    end
  end

  # Runs
  @spec list_runs(map()) :: [Run.t()]
  def list_runs(params) do
    Repo.all(Run.filter(params))
  end

  def deactivate_runs(device_id) do
    Repo.update_all(Run.deactivate_query(device_id), set: [active: false])
  end

  defp recording_path(%{device_id: device_id, start_date: start_date}) do
    directory = Application.get_env(:ex_nvr, :recording_directory)
    Path.join([directory, device_id, "#{DateTime.to_unix(start_date, :microsecond)}.mp4"])
  end
end
