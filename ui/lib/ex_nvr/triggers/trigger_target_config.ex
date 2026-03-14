defmodule ExNVR.Triggers.TriggerTargetConfig do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @target_types ~w(log_message start_recording stop_recording)

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
    |> Changeset.validate_inclusion(:target_type, @target_types)
    |> validate_config()
  end

  defp validate_config(changeset) do
    case Changeset.get_field(changeset, :target_type) do
      "log_message" -> validate_log_message_config(changeset)
      _ -> changeset
    end
  end

  defp validate_log_message_config(changeset) do
    config = Changeset.get_field(changeset, :config) || %{}
    level = config["level"] || "info"

    if level in ~w(debug info warning error) do
      changeset
    else
      Changeset.add_error(
        changeset,
        :config,
        "log level must be one of: debug, info, warning, error"
      )
    end
  end

  def target_types, do: @target_types
end
