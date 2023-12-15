defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """
  import Ecto.Query

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
      |> Multi.insert(:run, run, on_conflict: {:replace_all_except, [:start_date]})
      |> Repo.transaction()
      |> case do
        {:ok, %{recording: recording, run: run}} ->
          Phoenix.PubSub.broadcast(
            ExNVR.PubSub,
            "new_runs",
            :runs
          )
          {:ok, recording, run}
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

  @spec get(Device.t(), binary()) :: Recording.t() | nil
  def get(%Device{id: id}, filename) do
    Repo.one(Recording.get_query(id, filename))
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

  @spec delete_oldest_recordings(Device.t(), integer()) ::
          :ok | {:error, Ecto.Changeset.t()}
  def delete_oldest_recordings(device, limit) do
    recordings = Recording.oldest_recordings(device.id, limit) |> Repo.all()

    oldest_recording_query = Recording.oldest_recordings(device.id, 1)
    delete_recordings_query = from(r in Recording, where: r.id in ^Enum.map(recordings, & &1.id))

    base_run_query = from(r in Run, where: r.device_id == ^device.id)
    oldest_run_query = from(r in base_run_query, order_by: r.start_date, limit: 1)

    Multi.new()
    |> Multi.delete_all(:recordings, delete_recordings_query)
    |> Multi.one(:oldest_recording, oldest_recording_query)
    |> Multi.delete_all(:runs, fn %{oldest_recording: recording} ->
      from(r in base_run_query, where: r.end_date < ^recording.start_date)
    end)
    |> Multi.one(:oldest_run, oldest_run_query)
    |> Multi.update(:run, fn %{oldest_run: run, oldest_recording: recording} ->
      Run.changeset(run, %{start_date: recording.start_date})
    end)
    |> Multi.run(:delete_files, fn _repo, _params ->
      recordings
      |> Enum.map(&recording_path(device, &1))
      |> Enum.each(&File.rm!/1)

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _params} ->
        Phoenix.PubSub.broadcast(
          ExNVR.PubSub,
          "new_runs",
          :runs
        )
        :telemetry.execute([:ex_nvr, :recording, :delete], %{count: length(recordings)}, %{
          device_id: device.id
        })

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  defp copy_file(_device, _params, false), do: :ok

  defp copy_file(device, params, true) do
    File.cp(params.path, recording_path(device, params))
  end
end
