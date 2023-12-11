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
      |> Multi.insert(:run, run, on_conflict: {:replace_all_except, [:start_date]})
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
          {:ok, Ecto.Schema.t()} | {:error, Ecto.Changeset.t()}
  def delete_oldest_recordings(device, limit) do
    recordings =
      Recording.oldest_recordings_by_device(device.id, limit)
      |> Repo.all()

    oldest_recording = List.first(recordings)

    runs =
      Run.before_date(
        device.id,
        List.last(recordings)
        |> Map.get(:start_date)
      )
      |> Repo.all()

    IO.inspect(List.last(runs))
    IO.inspect(oldest_recording.end_date)

    Multi.new()
    # Delete recordings from db
    |> Multi.delete_all(
      :delete_recordings,
      Recording.list_recordings(Enum.map(recordings, & &1.id))
    )
    # delete all the runs that have start date less than the start date of the oldest recording
    |> Multi.delete_all(
      :delete_runs,
      Run.list_runs(Enum.map(runs, & &1.id))
    )
    # update the oldest run start date to match the start date of the oldest recording
    |> Multi.run(:update_run, fn _repo, _params ->
      date = List.last(recordings) |> Map.get(:end_date)

      Run.between_dates(date, device.id)
      |> Repo.one()
      |> case do
        nil ->
          {:ok, nil}

        run ->
          run
          |> Map.put(:start_date, date)
          |> Repo.insert(on_conflict: :replace_all)
      end
    end)
    # delete all the recording files
    |> Multi.run(:delete_files, fn _repo, _params ->
      Enum.each(recordings, fn recording ->
        recording_path(device, recording)
        |> File.rm!()
      end)

      {:ok, nil}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _changes} ->
        :telemetry.execute([:ex_nvr, :recording, :delete], %{count: length(recordings)}, %{
          device_id: device.id
        })

        :ok

      {:error, _, changeset, _} ->
        {:error, changeset}
    end
  end

  defp copy_file(_device, _params, false), do: :ok

  defp copy_file(device, params, true) do
    File.cp(params.path, recording_path(device, params))
  end
end
