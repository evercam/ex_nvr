defmodule ExNVRWeb.Components.Evercam do
  use Phoenix.Component

  def logo(assigns) do
    ~H"""
    <img
      src="https://evercam.io/wp-content/themes/evercam/img/white-logo.svg"
      class="h-8 mr-3"
      alt="Evercam Logo"
    />
    """
  end
end
