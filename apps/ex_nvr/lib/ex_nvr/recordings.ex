defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings and recordings metadata
  """

  alias ExNVR.Model.{Device, Recording}
  alias ExNVR.Repo

  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec create(map()) :: {:ok, Recording.t()} | error()
  def create(%{path: path} = params) do
    with {:ok, data} <- File.read(path),
         :ok <- File.write(recording_path(params), data) do
      params
      |> Map.put(:filename, recording_path(params) |> Path.basename())
      |> Recording.changeset()
      |> Repo.insert()
    end
  end

  @spec get_blob(Device.t(), binary()) :: binary() | nil
  def get_blob(%Device{id: id}, filename) do
    with %Recording{} = rec <- Repo.get_by(Recording, %{device_id: id, filename: filename}) do
      File.read!(recording_path(rec))
    end
  end

  defp recording_path(%{start_date: start_date}) do
    directory = Application.get_env(:ex_nvr, :recording_directory)
    Path.join(directory, "#{DateTime.to_unix(start_date, :microsecond)}.mp4")
  end
end
