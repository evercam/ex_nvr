defmodule ExNVR.Recordings do
  @moduledoc """
  Context to create/update/delete recordings metadata
  """

  alias ExNVR.Model.Recording

  @recordings_dir "./data/recordings"

  @type error :: {:error, Ecto.Changeset.t() | File.posix()}

  @spec save(map()) :: {:ok, Recording.t()} | error()
  def save(%{path: path} = params) do
    with {:ok, data} <- File.read(path),
         :ok <- File.write(recording_path(params), data) do
      params
      |> Map.put(:filename, recording_path(params) |> Path.basename())
      |> Recording.changeset()
      |> ExNVR.Repo.insert()
    end
  end

  defp recording_path(%{start_date: start_date}) do
    Path.join(@recordings_dir, "#{DateTime.to_unix(start_date, :microsecond)}.mp4")
  end
end
