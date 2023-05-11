defmodule ExNVR.Model.Recording do
  @moduledoc false

  use Ecto.Schema

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

  def changeset(params) do
    %__MODULE__{}
    |> Changeset.cast(params, @required_fields)
    |> Changeset.validate_required(@required_fields)
  end
end
