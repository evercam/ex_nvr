defmodule EvercamPlugin do
  @behaviour ExNVRWeb.Plugin

  def routes()  do
    [
      {"/kit", ExNVRWeb.KitDetailsLive, :index}
    ]
  end

  def menu_entries(), do: [
    %{
      label: "Kit sDetails",
      href: "/kit",
      icon: "hero-cube",
      position: [group: 1, index: 0]
    }
  ]

  def components() do
    %{
      logo: &ExNVRWeb.Components.Evercam.logo/1
    }
  end

  def assets() do
    [
      {:js, :head, "code-editor.js"}
    ]
  end
end
