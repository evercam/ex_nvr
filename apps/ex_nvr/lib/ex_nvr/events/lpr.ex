defmodule ExNVR.Events.LPR do
  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @fields [:capture_time, :plate_number, :direction, :list_type, :device_id]

  @derive {Flop.Schema,
           filterable: [
             :capture_time,
             :plate_number,
             :direction,
             :list_type,
             :device_id
           ],
           sortable: [:device_id, :capture_time],
           default_order: %{
             order_by: [:device_id, :capture_time],
             order_directions: [:asc, :desc]
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

  defmodule Metadata do
    use Ecto.Schema

    alias Ecto.Changeset

    @type t :: %__MODULE__{}

    @primary_key false
    embedded_schema do
      field :confidence, :float
      field :bounding_box, {:array, :float}
      field :plate_color, :string
      field :vehicle_type, :string
      field :vehicle_color, :string
    end

    @spec changeset(t(), map()) :: Changeset.t()
    def changeset(box, attrs) do
      box
      |> Changeset.cast(attrs, __MODULE__.__schema__(:fields))
      |> Changeset.validate_change(:bounding_box, fn :bounding_box, values ->
        cond do
          length(values) != 4 ->
            [bounding_box: "array must have 4 values"]

          Enum.any?(values, &(&1 < 0 or &1 > 1)) ->
            [bounding_box: "all values must be in the range [0..1]"]

          true ->
            []
        end
      end)
    end
  end

  @foreign_key_type :binary_id
  schema "lpr_events" do
    field :capture_time, :utc_datetime_usec
    field :plate_number, :string
    field :direction, Ecto.Enum, values: [:in, :away, :unknown], default: :unknown
    field :list_type, Ecto.Enum, values: [:white, :black, :other]

    embeds_one :metadata, Metadata, on_replace: :update

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

  @spec plate_name(t()) :: binary()
  def plate_name(%__MODULE__{id: id, plate_number: number}), do: "#{id}_#{number}.jpg"

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, @fields)
    |> Changeset.cast_embed(:metadata)
    |> Changeset.validate_required([:capture_time, :plate_number])
  end
end
