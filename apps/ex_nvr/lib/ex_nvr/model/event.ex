defmodule ExNVR.Model.Event do
  use Ecto.Schema

  import Ecto.Query

  alias Ecto.Changeset

  @type t :: %__MODULE__{
          capture_time: DateTime.t(),
          plate_number: binary(),
          direction: binary(),
          device_id: binary()
        }

  @foreign_key_type :binary_id
  schema "events" do
    field :capture_time, :utc_datetime_usec
    field :plate_number, :string
    field :direction, :string
    field :type, :string

    belongs_to :device, ExNVR.Model.Device
  end

  def with_device(query \\ __MODULE__, device_id) do
    where(query, [r], r.device_id == ^device_id)
  end

  def with_type(query \\ __MODULE__, type) do
    where(query, [r], r.type == ^type)
  end

  def changeset(event \\ %__MODULE__{}, params) do
    event
    |> Changeset.cast(params, __MODULE__.__schema__(:fields))
    |> Changeset.validate_required([:capture_time, :plate_number, :direction, :type])
  end
end
