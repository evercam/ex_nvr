defmodule ExNVR.Triggers.TriggerTargetConfig do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset
  alias ExNVR.Triggers.TriggerTargets

  @type t :: %__MODULE__{}

  schema "trigger_target_configs" do
    field :target_type, :string
    field :config, :map, default: %{}
    field :enabled, :boolean, default: true

    belongs_to :trigger_config, ExNVR.Triggers.TriggerConfig

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(target_config \\ %__MODULE__{}, params) do
    target_config
    |> Changeset.cast(params, [:target_type, :config, :enabled, :trigger_config_id])
    |> Changeset.validate_required([:target_type, :trigger_config_id])
    |> validate_config()
  end

  defp validate_config(changeset) do
    target_type = Changeset.get_field(changeset, :target_type)
    config = Changeset.get_field(changeset, :config) || %{}

    case TriggerTargets.module_for(target_type) do
      nil ->
        Changeset.add_error(changeset, :target_type, "unknown target type")

      module ->
        case module.validate_config(config) do
          {:ok, validated} ->
            Changeset.put_change(changeset, :config, validated)

          {:error, errors} ->
            Enum.reduce(errors, changeset, fn {field, msg}, cs ->
              Changeset.add_error(cs, :config, "#{field}: #{msg}")
            end)
        end
    end
  end
end
