defmodule ExNVR.Triggers.TriggerSourceConfig do
  @moduledoc false

  use Ecto.Schema

  alias Ecto.Changeset

  @type t :: %__MODULE__{}

  @source_types ~w(event)

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
    |> Changeset.validate_inclusion(:source_type, @source_types)
    |> validate_config()
  end

  defp validate_config(changeset) do
    case Changeset.get_field(changeset, :source_type) do
      "event" -> validate_event_config(changeset)
      _ -> changeset
    end
  end

  defp validate_event_config(changeset) do
    config = Changeset.get_field(changeset, :config) || %{}

    if is_binary(config["event_type"]) and config["event_type"] != "" do
      changeset
    else
      Changeset.add_error(changeset, :config, "event source requires an event_type")
    end
  end

  def source_types, do: @source_types
end
