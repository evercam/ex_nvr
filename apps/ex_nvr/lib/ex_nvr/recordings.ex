defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """

  alias Ecto.Multi
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.{Repo, Utils}

  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec create(Run.t(), map(), boolean()) :: {:ok, Recording.t(), Run.t()} | error()
  def create(%Run{} = run, params, copy_file? \\ true) do
    params = if is_struct(params), do: Map.from_struct(params), else: params

    with :ok <- copy_file(params, copy_file?) do
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

  @spec list(map()) :: {:ok, {[map()], Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def list(params \\ %{}) do
    Recording.list_with_devices()
    |> ExNVR.Flop.validate_and_run(params, for: Recording)
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
  @spec list_runs(map() | Keyword.t()) :: [Run.t()]
  def list_runs(params) do
    Repo.all(Run.filter(params))
  end

  def deactivate_runs(%Device{id: device_id}) do
    Repo.update_all(Run.deactivate_query(device_id), set: [active: false])
  end

  defp copy_file(_params, false), do: :ok

  defp copy_file(params, true) do
    File.cp(params.path, recording_path(params))
  end

  defp recording_path(%{device_id: device_id, start_date: start_date}) do
    Path.join(Utils.recording_dir(device_id), "#{DateTime.to_unix(start_date, :microsecond)}.mp4")
  end
end
