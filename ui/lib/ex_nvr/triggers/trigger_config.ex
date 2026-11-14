defmodule ExNVR.Triggers.TriggerConfig do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset
  alias ExNVR.Triggers.{DeviceTriggerConfig, TriggerSourceConfig, TriggerTargetConfig}

  @type t :: %__MODULE__{}

  schema "trigger_configs" do
    field :name, :string
    field :enabled, :boolean, default: true

    has_many :source_configs, TriggerSourceConfig
    has_many :target_configs, TriggerTargetConfig

    many_to_many :devices, ExNVR.Model.Device,
      join_through: DeviceTriggerConfig,
      on_replace: :delete

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(trigger_config \\ %__MODULE__{}, params) do
    trigger_config
    |> Changeset.cast(params, [:name, :enabled])
    |> Changeset.validate_required([:name])
    |> Changeset.unique_constraint(:name)
  end
end
