defmodule ExNVR.Model.Run do
  @moduledoc """
  A run represent a recording session.

  An example of a run would be an RTSP session from start to finish. It's a helpful
  module to get the available footages
  """

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          active: boolean(),
          device_id: binary()
        }

  @foreign_key_type :binary_id
  schema "runs" do
    field(:start_date, :utc_datetime_usec)
    field(:end_date, :utc_datetime_usec)
    field(:active, :boolean, default: false)

    belongs_to :device, ExNVR.Model.Device
  end

  def deactivate_query(device_id) do
    from(r in __MODULE__, where: r.device_id == ^device_id and r.active == true)
  end

  def before_date(query \\ __MODULE__, device_id, date) do
    from(r in query,
      where: r.device_id == ^device_id and r.start_date < ^date,
      order_by: r.start_date
    )
  end

  def between_dates(query \\ __MODULE__, date, device_id) do
    where(query, [r], r.device_id == ^device_id and r.start_date <= ^date and r.end_date >= ^date)
  end

  def list_runs_by_device(query \\ __MODULE__, device_id) do
    from(r in query,
      where: r.device_id == ^device_id,
      order_by: r.start_date
    )
  end

  def list_runs_by_ids(query \\ __MODULE__, ids) do
    where(query, [r], r.id in ^ids)
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:device_id, id}, q -> where(q, [r], r.device_id == ^id)
      {:start_date, start_date}, q -> where(q, [r], r.end_date > ^start_date)
      _, q -> q
    end)
    |> order_by([r], asc: r.device_id, asc: r.start_date)
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> Changeset.cast(params, __MODULE__.__schema__(:fields))
  end
end
