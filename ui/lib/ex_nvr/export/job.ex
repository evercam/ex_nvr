defmodule ExNVR.Export.Job do
  @moduledoc """
  Index entry of an export job. The job's state is its manifest (see
  `ExNVR.Export.Manifest`); this only records where to find it.
  """

  use Ecto.Schema

  @type t :: %__MODULE__{
          id: integer() | nil,
          dest_dir: Path.t(),
          device_id: binary(),
          kind: :usb | :s3,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  schema "export_jobs" do
    field :dest_dir, :string
    field :device_id, :string
    field :kind, Ecto.Enum, values: [:usb, :s3]

    timestamps(type: :utc_datetime_usec)
  end
end
