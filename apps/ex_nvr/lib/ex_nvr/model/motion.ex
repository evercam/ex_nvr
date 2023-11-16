defmodule ExNVR.Model.Motion do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @type t :: %__MODULE__{
    id: integer(),
    label: binary(),
    time: DateTime.t(),
    device: ExNVR.Model.Device.t(),
    dimentions: MotionLabelDimention.t(),
    inserted_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  defmodule MotionLabelDimention do
    use Ecto.Schema

    import Ecto.Changeset

    @type t :: %__MODULE__{
            x: integer(),
            y: integer(),
            width: integer(),
            height: integer()
          }

    @required_fields [:x, :y, :width, :height]

    @primary_key false
    embedded_schema do
      field :x, :integer
      field :y, :integer
      field :width, :integer
      field :height, :integer
    end

    defimpl Jason.Encoder do
      def encode(%MotionLabelDimention{x: x, y: y, width: width, height: height}, opts) do
        Jason.Encode.map(%{
          "x" => x,
          "y" => y,
          "width" => width,
          "height" => height,
        }, opts)
      end
    end

    def changeset(struct, params) do
      struct
      |> cast(params, __MODULE__.__schema__(:fields))
      |> validate_required(@required_fields)
    end
  end

  @foreign_key_type :binary_id
  schema "motions" do
    field :label, :string, default: "Unknown"
    field :time, :utc_datetime_usec
    embeds_one :dimentions, MotionLabelDimention, source: :dimentions, on_replace: :update
    belongs_to :device, ExNVR.Model.Device

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(struct, params) do
    struct
    |> Changeset.cast(params, [:label, :time, :device_id])
    |> Changeset.cast_embed(:dimentions)
    |> Changeset.validate_required([:dimentions, :device_id])
  end
end
