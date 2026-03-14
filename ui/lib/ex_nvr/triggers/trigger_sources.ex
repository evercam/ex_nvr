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
