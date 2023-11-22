defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """

  alias Ecto.Multi
  alias ExNVR.Model.{Device, Recording, Run}
  alias ExNVR.Repo

  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec create(Device.t(), Run.t(), map(), boolean()) :: {:ok, Recording.t(), Run.t()} | error()
  def create(%Device{} = device, %Run{} = run, params, copy_file? \\ true) do
    params = if is_struct(params), do: Map.from_struct(params), else: params

    with :ok <- copy_file(device, params, copy_file?) do
      recording_changeset =
        params
        |> Map.put(:filename, recording_path(device, params) |> Path.basename())
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

  @spec index(binary()) :: [Recording.t()]
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
    if recording = Repo.one(Recording.get_query(id, filename)) do
      File.read!(recording_path(recording.device, recording))
    end
  end

  # Runs
  @spec list_runs(map() | Keyword.t()) :: [Run.t()]
  def list_runs(params) do
    Repo.all(Run.filter(params))
  end

  @spec deactivate_runs(Device.t()) :: {non_neg_integer(), nil | term()}
  def deactivate_runs(%Device{id: device_id}) do
    Repo.update_all(Run.deactivate_query(device_id), set: [active: false])
  end

  @spec recording_path(Device.t(), map()) :: Path.t()
  def recording_path(device, %{start_date: start_date}) do
    Path.join(
      [Device.recording_dir(device) | ExNVR.Utils.date_components(start_date)] ++
        ["#{DateTime.to_unix(start_date, :microsecond)}.mp4"]
    )
  end

  defp copy_file(_device, _params, false), do: :ok

  defp copy_file(device, params, true) do
    File.cp(params.path, recording_path(device, params))
  end
end
