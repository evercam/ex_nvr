defmodule ExNVR.Model.LPREvent do
  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @fields [
    :capture_time,
    :plate_number,
    :direction,
    :list_type,
    :confidence,
    :vehicle_type,
    :vehicle_color,
    :plate_color,
    :device_id
  ]

  @derive {Flop.Schema,
           filterable: [
             :capture_time,
             :plate_number,
             :direction,
             :list_type,
             :vehicle_type,
             :vehicle_color,
             :plate_color,
             :inserted_at,
             :device_id
           ],
           sortable: [:inserted_at, :capture_time, :confidence],
           default_order: %{
             order_by: [:inserted_at, :capture_time, :confidence],
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
          capture_time: DateTime.t(),
          plate_number: binary(),
          direction: binary(),
          list_type: binary(),
          confidence: float(),
          vehicle_type: binary(),
          vehicle_color: binary(),
          plate_color: binary(),
          bounding_box: BoundingBox.t(),
          device_id: binary(),
          device: ExNVR.Model.Device.t(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defmodule BoundingBox do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            x1: integer(),
            y1: integer(),
            x2: integer(),
            y2: integer()
          }

    @primary_key false
    embedded_schema do
      field :x1, :integer
      field :y1, :integer
      field :x2, :integer
      field :y2, :integer
    end

    def changeset(box, attrs) do
      box
      |> cast(attrs, [:x1, :y1, :x2, :y2])
      |> validate_required([:x1, :y1, :x2, :y2])
    end
  end

  @foreign_key_type :binary_id
  schema "lpr_events" do
    field :capture_time, :utc_datetime_usec
    field :plate_number, :string
    field :direction, Ecto.Enum, values: [:forward, :reverse]
    field :list_type, Ecto.Enum, values: [:white, :black, :visitor]
    field :confidence, :float
    field :vehicle_type, :string
    field :vehicle_color, :string
    field :plate_color, :string

    embeds_one :bounding_box, BoundingBox, on_replace: :update

    belongs_to :device, ExNVR.Model.Device

    timestamps(type: :utc_datetime_usec)
  end

  @spec list_with_device(any()) :: Ecto.Query.t()
  def list_with_device(query \\ __MODULE__) do
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

  def with_device(query \\ __MODULE__, device_id) do
    where(query, [r], r.device_id == ^device_id)
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, @fields)
    |> Changeset.cast_embed(:bounding_box)
    |> Changeset.validate_required([:capture_time, :plate_number])
  end
end
