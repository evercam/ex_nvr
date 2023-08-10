defmodule ExNVR.Model.Recording do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          filename: binary()
        }

  @required_fields [:device_id, :start_date, :end_date, :filename]

  @foreign_key_type :binary_id
  schema "recordings" do
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :filename, :string

    belongs_to :device, ExNVR.Model.Device
  end

  def between_dates(query \\ __MODULE__, start_date, end_date, opts) do
    where(query, [r], r.start_date <= ^end_date and r.end_date > ^start_date)
    |> limit(^(opts[:limit] || 50))
    |> order_by(asc: :start_date)
  end

  def with_device(query \\ __MODULE__, device_id) do
    where(query, [r], r.device_id == ^device_id)
  end

  def changeset(params) do
    %__MODULE__{}
    |> Changeset.cast(params, @required_fields)
    |> Changeset.validate_required(@required_fields)
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:state, value}, q when is_atom(value) -> where(q, [r], r.device_id == ^value)
      {:state, values}, q when is_list(values) -> where(q, [r], r.device_id in ^values)
      _, q -> q
    end)
  end
end
