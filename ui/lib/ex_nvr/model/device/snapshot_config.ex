defmodule ExNVR.Model.Device.SnapshotConfig do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias ExNVR.Model.Schedule

  @type t :: %__MODULE__{
          enabled: boolean(),
          upload_interval: integer(),
          remote_storage: binary(),
          schedule: map()
        }

  @primary_key false
  embedded_schema do
    field :enabled, :boolean
    field :upload_interval, :integer, default: 30
    field :remote_storage, :string
    field :schedule, :map
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(struct, params) do
    changeset = cast(struct, params, __MODULE__.__schema__(:fields))
    enabled = get_field(changeset, :enabled)
    validate_config(changeset, enabled)
  end

  defp validate_config(changeset, true) do
    changeset
    |> validate_required([:upload_interval, :remote_storage])
    |> validate_number(:upload_interval,
      greater_than_or_equal_to: 5,
      less_than_or_equal_to: 3600
    )
    |> validate_schedule()
  end

  defp validate_config(changeset, _enabled) do
    changeset
    |> put_change(:upload_interval, 0)
    |> put_change(:remote_storage, nil)
    |> put_change(:schedule, %{})
  end

  defp validate_schedule(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_schedule(changeset) do
    schedule = get_field(changeset, :schedule)
    do_validate_schedule(changeset, schedule)
  end

  defp do_validate_schedule(changeset, nil), do: changeset

  defp do_validate_schedule(changeset, schedule) do
    case Schedule.validate(schedule) do
      {:ok, schedule} ->
        put_change(changeset, :schedule, schedule)

      {:error, :invalid_schedule_days} ->
        add_error(changeset, :schedule, "Invalid schedule days")

      {:error, :invalid_time_intervals} ->
        add_error(changeset, :schedule, "Invalid schedule time intervals format")

      {:error, :invalid_time_interval_range} ->
        add_error(
          changeset,
          :schedule,
          "Invalid schedule time intervals range (start time must be before end time)"
        )

      {:error, :overlapping_intervals} ->
        add_error(changeset, :schedule, "Schedule time intervals must not overlap")
    end
  end
end
