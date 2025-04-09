defmodule ExNVR.Events.Event do
  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @derive {Flop.Schema,
           filterable: [
             :event_time,
             :event_type,
             :device_id
           ],
           sortable: [:event_time, :event_type],
           default_order: %{
             order_by: [:event_time],
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
    field(:event_time, :utc_datetime_usec)
    field(:event_type, :string)
    field(:event_data, :map, default: %{})

    belongs_to(:device, ExNVR.Model.Device)

    timestamps(type: :utc_datetime_usec)
  end

  def filter(query \\ __MODULE__, params) do
    Enum.reduce(params, query, fn
      {"device_id", device_id}, q -> where(q, [e], e.device_id == ^device_id)
      {"event_type", event_type}, q -> where(q, [e], e.event_type == ^event_type)
      {"start_date", start_date}, q -> where(q, [e], e.event_time >= ^start_date)
      {"end_date", end_date}, q -> where(q, [e], e.event_time <= ^end_date)
      _, q -> q
    end)
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, [:event_time, :event_type, :event_data, :device_id])
    |> Changeset.validate_required([:event_type, :device_id])
    |> Changeset.validate_change(:event_data, fn :event_data, event_data ->
      case Jason.encode(event_data) do
        {:ok, _json} -> []
        {:error, _reason} -> [event_data: "must be JSON serializable"]
      end
    end)
  end
end
