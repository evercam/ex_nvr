defmodule ExNVR.Model.Device.StorageConfig do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias ExNVR.Model.Schedule

  @type t :: %__MODULE__{}

  @primary_key false
  embedded_schema do
    field :recording_mode, Ecto.Enum, values: [:none, :always, :on_event], default: :always
    field :address, :string
    # full drive
    field :full_drive_threshold, :float, default: 95.0
    field :full_drive_action, Ecto.Enum, values: [:nothing, :overwrite], default: :overwrite
    # Sub stream
    field :record_sub_stream, Ecto.Enum, values: [:never, :always], default: :never
    field :schedule, :map
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
    |> cast(params, [
      :recording_mode,
      :address,
      :full_drive_threshold,
      :full_drive_action,
      :record_sub_stream,
      :schedule
    ])
    |> common_changeset()
  end

  defp common_changeset(changeset) do
    changeset
    |> validate_number(:full_drive_threshold,
      less_than_or_equal_to: 100,
      greater_than_or_equal_to: 0,
      message: "value must be between 0 and 100"
    )
    |> maybe_require_address()
    |> validate_change(:schedule, fn :schedule, schedule ->
      case Schedule.validate(schedule) do
        {:ok, _schedule} -> []
        {:error, _reason} -> [schedule: "Invalid schedule"]
      end
    end)
  end

  defp maybe_require_address(changeset) do
    recording_mode = get_field(changeset, :recording_mode)

    if recording_mode != :none do
      validate_required(changeset, [:address])
    else
      changeset
    end
  end
end
