defmodule ExNVR.Triggers.TriggerSourceConfig do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset
  alias ExNVR.Triggers.TriggerSources

  @type t :: %__MODULE__{}

  schema "trigger_source_configs" do
    field :source_type, :string
    field :config, :map, default: %{}

    belongs_to :trigger_config, ExNVR.Triggers.TriggerConfig

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(source_config \\ %__MODULE__{}, params) do
    source_config
    |> Changeset.cast(params, [:source_type, :config, :trigger_config_id])
    |> Changeset.validate_required([:source_type, :trigger_config_id])
    |> validate_config()
  end

  defp validate_config(changeset) do
    source_type = Changeset.get_field(changeset, :source_type)
    config = Changeset.get_field(changeset, :config) || %{}

    case TriggerSources.module_for(source_type) do
      nil ->
        Changeset.add_error(changeset, :source_type, "unknown source type")

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
