defmodule ExNVR.SystemInformation.Disk do
  @moduledoc """
  A module representing a storage device: HDD, SSD, memory card, ...etc.
  """

  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{
    vendor: binary() | nil,
    model: binary(),
    serial: binary(),
    type: binary() | nil,
    size: integer(),
    transport: binary() | nil,
    hotplug: boolean() | nil,
    inserted_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil
  }

  schema "storage_devices" do
    field :vendor, :string
    field :model, :string
    field :serial, :string
    field :type, :string
    field :size, :integer
    field :transport, :string
    field :hotplug, :boolean, default: false

    timestamps(type: :utc_datetime_usec)
  end

  @spec changeset(map()) :: Changeset.t()
  def changeset(params) do
    IO.inspect(params)
    %__MODULE__{}
    |> Changeset.cast(params, __MODULE__.__schema__(:fields))
    |> Changeset.validate_required([:model, :serial, :size])
  end
end
