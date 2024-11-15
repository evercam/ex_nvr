defmodule ExNVR.Model.Recording do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [:start_date, :end_date, :device_id],
           sortable: [:start_date, :end_date, :device_name, :device_id],
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

  @type t :: %__MODULE__{}

  @required_fields [:device_id, :start_date, :end_date, :filename]

  @foreign_key_type :binary_id
  schema "recordings" do
    field :start_date, :utc_datetime_usec
    field :end_date, :utc_datetime_usec
    field :filename, :string
    field :stream, Ecto.Enum, values: [:high, :low], default: :high

    belongs_to :device, ExNVR.Model.Device
    belongs_to :run, ExNVR.Model.Run, type: :integer
  end

  def with_type(query \\ __MODULE__, stream_type) do
    where(query, [r], r.stream == ^stream_type)
  end

  def before_date(query \\ __MODULE__, date) do
    where(query, [r], r.end_date < ^date)
  end

  def between_dates(query \\ __MODULE__, start_date, end_date, opts) do
    where(query, [r], r.start_date <= ^end_date and r.end_date > ^start_date)
    |> limit(^(opts[:limit] || 50))
    |> order_by(asc: :start_date)
  end

  def with_device(query \\ __MODULE__, device_id) do
    where(query, [r], r.device_id == ^device_id)
  end

  def get_query(query \\ __MODULE__, device_id, name) do
    from(r in query, where: r.device_id == ^device_id and r.filename == ^name)
  end

  def oldest_recordings(query \\ __MODULE__, device_id, limit) do
    from(r in query,
      where: r.device_id == ^device_id,
      order_by: r.start_date,
      limit: ^limit
    )
  end

  def list_with_devices(query) do
    from(r in query,
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

  def list_recordings(query \\ __MODULE__, ids) do
    where(query, [r], r.id in ^ids)
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
    |> Changeset.cast(params, @required_fields ++ [:stream, :run_id])
    |> Changeset.validate_required(@required_fields)
  end
end
