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
    |> TriggerSources.validate_config()
  end
end
