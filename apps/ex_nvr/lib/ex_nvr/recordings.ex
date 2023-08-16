defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """

  alias Ecto.Multi
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.{Repo, Utils}

  import Ecto.Query

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

  @spec index(binary()) :: [
          Recording.t()
        ]
  def index(device_id) do
    Recording.with_device(device_id)
    |> Repo.all()
  end

  def list(params \\ %{}) do
    params
    |> Recording.filter()
    |> order_by([r], desc: r.start_date)
    |> preload([:device])
    |> Repo.all()
  end

  def paginate_recordings(params \\ []) do
    Recording.filter(params)
    |> order_by([r], desc: r.start_date)
    |> preload([:device])
    |> Repo.paginate(params)
  end

  @spec get_recordings_between(binary(), DateTime.t(), DateTime.t(), Keyword.t()) :: [
          Recording.t()
        ]
  def get_recordings_between(device_id, start_date, end_date, opts \\ []) do
    start_date
    |> Recording.between_dates(end_date, opts)
    |> Recording.with_device(device_id)
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

  def deactivate_runs(%Device{id: device_id}) do
    Repo.update_all(Run.deactivate_query(device_id), set: [active: false])
  end

  defp recording_path(%{device_id: device_id, start_date: start_date}) do
    Path.join(Utils.recording_dir(device_id), "#{DateTime.to_unix(start_date, :microsecond)}.mp4")
  end
end
