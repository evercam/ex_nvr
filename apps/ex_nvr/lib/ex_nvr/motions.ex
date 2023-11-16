defmodule ExNVR.Motions do
  alias ExNVR.Model.Motion
  alias ExNVR.Repo

  import Ecto.Query

  @spec create(map()) :: [Motion.t()]
  def create(params) do
    %Motion{}
    |> Motion.changeset(params)
    |> Repo.insert()
  end

  @spec create_all([map()]) :: [[Motion.t()]]
  def create_all(entries) do
    Repo.insert_all(Motion, entries)
  end

  @spec get_motions_from_time(binary(), DateTime.t()) :: [[Motion.t()]]
  def get_motions_from_time(device_id, time) do
    where(
      Motion,
      [r],
      r.time <= ^DateTime.add(time, 1, :second) and r.time >= ^DateTime.add(time, -1, :second)
      and r.device_id == ^device_id
    )
    |> limit(50)
    |> order_by(asc: :time)
    |> Repo.all()
    |> Repo.preload(:device)
  end
end
