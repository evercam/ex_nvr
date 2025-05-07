defmodule ExNVRWeb.Plugin do
  @moduledoc "Plugin behavior for extending the ExNVR dashboard."

  @type menu_entry :: %{
    required(:name) => String.t(),
    required(:route) => String.t(),
    optional(:icon) => String.t(),
    optional(:position) => integer()
  }

  @doc """
  List of additional Phoenix routes as tuples of shape `{path, module, action}`
  """
  @callback routes() :: [{String.t(), module(), atom()}]

  @doc """
  List of additional menu entries
  """
  @callback menu_entries() :: [menu_entry()]

  @doc """
  List of component overrides
  """
  @callback components() :: %{ String.t() => (map() -> Phoenix.LiveView.Rendered.t()) }

  @doc """
  List of additional assets to include in the main HTML
  """
  @callback assets() :: [{:js | :css, :head | :body, String.t()}]

  @optional_callbacks [
    routes: 0,
    menu_entries: 0,
    components: 0,
    assets: 0
  ]
end
