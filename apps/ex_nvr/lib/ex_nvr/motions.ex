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

  @spec get_closest_time(DateTime.t(), binary()) :: [DateTime.t()]
  def get_closest_time(time, device_id) do
    from(m in Motion)
    |> where([m], m.device_id == ^device_id and m.time <= ^time)
    |> order_by(desc: :time)
    |> limit(1)
    |> Repo.one()
    |> then(&(&1.time))
  end

  @spec get_with_device_time(DateTime.t(), binary()) :: [[Motion.t()]]
  def get_with_device_time(time, device_id) do
    from(m in Motion)
    |> where(
      [m],
      m.device_id == ^device_id and m.time == ^time
    )
    |> order_by(desc: :time)
    |> Repo.all()
  end

  @spec get_latest_timestamp(binary()) :: [DateTime.t()]
  def get_latest_timestamp(device_id) do
    from(m in Motion)
    |> where([m], m.device_id == ^device_id)
    |> order_by(desc: :time)
    |> limit(1)
    |> Repo.one()
    |> then(&(&1.time))
  end
end
