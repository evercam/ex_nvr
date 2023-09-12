defmodule ExNVR.Model.Recording do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [:start_date, :end_date, :device_id],
           sortable: [:start_date, :end_date, :device_name],
           default_order: %{
             order_by: [:start_date, :end_date, :device_name],
             order_directions: [:desc]
           },
           adapter_opts: [
             join_fields: [
               device_name: [
                 binding: :joined_device,
                 field: :name,
                 ecto_type: :string
               ]
             ]
           ],
           pagination_types: [:page],
           default_limit: 100,
           max_limit: 150}

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

  def list_with_devices() do
    from(r in __MODULE__,
      join: d in assoc(r, :device),
      as: :joined_device,
      on: r.device_id == d.id,
      select: map(r, ^__MODULE__.__schema__(:fields)),
      select_merge: %{
        device_name: d.name,
        timezone: d.timezone
      }
    )
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {:device_id, value}, q when is_atom(value) -> where(q, [r], r.device_id == ^value)
      {:device_id, values}, q when is_list(values) -> where(q, [r], r.device_id in ^values)
      _, q -> q
    end)
  end

  def changeset(params) do
    %__MODULE__{}
    |> Changeset.cast(params, @required_fields)
    |> Changeset.validate_required(@required_fields)
  end
end
