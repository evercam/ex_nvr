defmodule ExNVRWeb.PluginRegistry do
  @moduledoc """
    Module for collecting and merging plugin-related data
    such as routes, menu entries, and components from
    the plugins defined in the application environment.
  """
  def plugins() do
    Application.get_env(:ex_nvr, :plugins, [])
  end

  def routes(), do: collect(:routes, [])

  def menu_entries(), do: collect(:menu_entries, [])

  def components(), do: collect(:components, %{})

  def render_component(name, assigns, fallback)  do
    components()
    |> Map.get_lazy(name, fn -> fallback end)
    |> then(& &1.(assigns))
  end

  def collect(collection, default) do
    plugins()
    |> Enum.map(&lookup(&1, collection, default))
    |> merge(default)
  end

  def collect_assets(type, position) do
    collect(:assets, [])
    |> Enum.filter(fn {t, p, _path} -> t == type and p == position end)
  end

  def assets_paths(type, position, :prod) do
    collect_assets(type, position)
    |> prefix_paths("/assets")
  end

  def assets_paths(:js, position, :dev) do
    collect_assets(:js, position)
    |> prefix_paths("/plugins/js")
  end

  def assets_paths(:css, position, :dev) do
    collect_assets(:css, position)
    |> prefix_paths("/plugins/css")
  end

  defp prefix_paths(paths, prefix) do
    Enum.map(paths, fn {t, p, path} -> "#{prefix}/#{path}" end)
  end

  defp lookup(plugin, collection, default) do
    case Code.ensure_loaded(plugin) do
      {:module, _} ->
        if function_exported?(plugin, collection, 0) do
          apply(plugin, collection, [])
        else
          default
        end

      _ ->
        IO.warn("Plugin #{inspect(plugin)} not loaded")
        default
    end
  end

  defp merge(results, %{}), do: Enum.reduce(results, %{}, &Map.merge/2)

  defp merge(results, []), do: List.flatten(results)
end
