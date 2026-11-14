defmodule ExNVR.Triggers.TriggerTargets do
  @moduledoc """
  Registry of available trigger target implementations.
  """

  alias ExNVR.Triggers.Targets

  @targets [
    {Targets.LogMessage, :log_message},
    {Targets.DeviceControl, :device_control}
  ]

  @spec list() :: [{module(), atom()}]
  def list, do: @targets

  @spec type_options() :: [{String.t(), String.t()}]
  def type_options do
    Enum.map(@targets, fn {mod, key} -> {mod.label(), Atom.to_string(key)} end)
  end

  @spec validate_config(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  def validate_config(changeset) do
    target_type = Ecto.Changeset.get_field(changeset, :target_type)
    config = Ecto.Changeset.get_field(changeset, :config) || %{}

    case module_for(target_type) do
      nil ->
        Ecto.Changeset.add_error(changeset, :target_type, "unknown target type")

      module ->
        apply_module_validation(changeset, module, config)
    end
  end

  defp apply_module_validation(changeset, module, config) do
    case module.validate_config(config) do
      {:ok, validated} ->
        Ecto.Changeset.put_change(changeset, :config, validated)

      {:error, errors} ->
        Enum.reduce(errors, changeset, fn {field, msg}, cs ->
          Ecto.Changeset.add_error(cs, :config, "#{field}: #{msg}")
        end)
    end
  end

  @spec module_for(atom() | String.t()) :: module() | nil
  def module_for(key) when is_binary(key) do
    module_for(String.to_existing_atom(key))
  rescue
    ArgumentError -> nil
  end

  def module_for(key) when is_atom(key) do
    case Enum.find(@targets, fn {_mod, k} -> k == key end) do
      {mod, _} -> mod
      nil -> nil
    end
  end
end
