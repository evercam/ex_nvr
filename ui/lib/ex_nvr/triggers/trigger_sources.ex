defmodule ExNVR.Triggers.TriggerSources do
  @moduledoc """
  Registry of available trigger source implementations.
  """

  alias ExNVR.Triggers.Sources

  @sources [
    {Sources.Event, :event}
  ]

  @spec list() :: [{module(), atom()}]
  def list, do: @sources

  @spec type_options() :: [{String.t(), String.t()}]
  def type_options do
    Enum.map(@sources, fn {mod, key} -> {mod.label(), Atom.to_string(key)} end)
  end

  @spec validate_config(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_config(changeset) do
    source_type = Ecto.Changeset.get_field(changeset, :source_type)
    config = Ecto.Changeset.get_field(changeset, :config) || %{}

    case module_for(source_type) do
      nil ->
        Ecto.Changeset.add_error(changeset, :source_type, "unknown source type")

      module ->
        case module.validate_config(config) do
          {:ok, validated} ->
            Ecto.Changeset.put_change(changeset, :config, validated)

          {:error, errors} ->
            Enum.reduce(errors, changeset, fn {field, msg}, cs ->
              Ecto.Changeset.add_error(cs, :config, "#{field}: #{msg}")
            end)
        end
    end
  end

  @spec module_for(atom() | String.t()) :: module() | nil
  def module_for(key) when is_binary(key) do
    module_for(String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  def module_for(key) when is_atom(key) do
    case Enum.find(@sources, fn {_mod, k} -> k == key end) do
      {mod, _} -> mod
      nil -> nil
    end
  end
end
