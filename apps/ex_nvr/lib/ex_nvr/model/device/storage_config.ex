defmodule ExNVR.Model.Device.StorageConfig do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :address, :string
    # full drive
    field :full_drive_threshold, :float, default: 95.0
    field :full_drive_action, Ecto.Enum, values: [:nothing, :overwrite], default: :nothing
    # Sub stream
    field :record_sub_stream, Ecto.Enum, values: [:never, :always], default: :never
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    struct
    |> cast(params, __MODULE__.__schema__(:fields))
    |> common_changeset()
    |> validate_change(:address, fn :address, mountpoint ->
      case File.stat(mountpoint) do
        {:ok, %File.Stat{access: :read_write}} -> []
        _other -> [address: "has no write permissions"]
      end
    end)
  end

  @spec update_changeset(t(), map()) :: Ecto.Changeset.t()
  def update_changeset(struct, params) do
    struct
    |> cast(params, [:full_drive_threshold, :full_drive_action, :record_sub_stream])
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    changeset
    |> validate_number(:full_drive_threshold,
      less_than_or_equal_to: 100,
      greater_than_or_equal_to: 0,
      message: "value must be between 0 and 100"
    )
    |> validate_required([:address])
  end
end
