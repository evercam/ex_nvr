defmodule ExNVR.Events.Event do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :time,
             :type,
             :device_id
           ],
           sortable: [:time, :type],
           default_order: %{
             order_by: [:time],
             order_directions: [:desc]
           },
           adapter_opts: [
             join_fields: [
               device_name: [
                 binding: :device,
                 field: :name,
                 ecto_type: :string
               ]
             ]
           ],
           pagination_types: [:page],
           default_limit: 20,
           max_limit: 50}

  @type t :: %__MODULE__{}

  @foreign_key_type :binary_id
  @derive {Jason.Encoder, except: [:device, :__meta__]}
  schema "events" do
    field :time, :utc_datetime_usec, autogenerate: {DateTime, :utc_now, []}
    field :type, :string
    field :metadata, :map, default: %{}

    belongs_to(:device, ExNVR.Model.Device)

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {"start_date", start_date}, q -> where(q, [e], e.time >= ^start_date)
      {"end_date", end_date}, q -> where(q, [e], e.time <= ^end_date)
      _, q -> q
    end)
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, [:time, :type, :metadata, :device_id])
    |> Changeset.validate_required([:type])
  end
end
