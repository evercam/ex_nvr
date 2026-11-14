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
    |> TriggerTargets.validate_config()
  end
end
