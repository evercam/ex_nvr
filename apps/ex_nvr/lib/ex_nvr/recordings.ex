defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """

  alias ExNVR.Model.{Device, Recording}
  alias ExNVR.Repo

  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec create(map()) :: {:ok, Recording.t()} | error()
  def create(%{path: path} = params) do
    params = if is_struct(params), do: Map.from_struct(params), else: params

    with {:ok, data} <- File.read(path),
         :ok <- File.write(recording_path(params), data) do
      params
      |> Map.put(:filename, recording_path(params) |> Path.basename())
      |> Recording.changeset()
      |> Repo.insert()
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

  defp recording_path(%{device_id: device_id, start_date: start_date}) do
    directory = Application.get_env(:ex_nvr, :recording_directory)
    Path.join([directory, device_id, "#{DateTime.to_unix(start_date, :microsecond)}.mp4"])
  end
end
