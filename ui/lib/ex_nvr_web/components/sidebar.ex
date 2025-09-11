defmodule ExNVRWeb.Components.Sidebar do
  @moduledoc false

  use ExNVRWeb, :live_component

  attr(:current_user, :map, required: false)
  attr(:current_path, :string, default: nil)

  def sidebar(assigns) do
    role = assigns.current_user && assigns.current_user.role

    assigns =
      groups()
      |> Enum.map(&filter_group_by_role(&1, role))
      |> Enum.reject(&(&1 == []))
      |> Enum.with_index()
      |> then(&Map.put(assigns, :groups, &1))

    ~H"""
    <aside
      id="logo-sidebar"
      class="fixed top-0 left-0 z-40 w-64 h-screen pt-20 transition-transform -translate-x-full bg-zinc-900 border-r border-white sm:translate-x-0 dark:bg-gray-800 dark:border-gray-700"
      aria-label="Sidebar"
    >
      <div class="flex flex-col justify-between h-full px-3 pb-4 overflow-y-auto bg-zinc-900 dark:bg-gray-800">
        <div>
          <.sidebar_group
            :for={{group, index} <- @groups}
            items={group}
            current_path={@current_path}
            border={index > 0}
          />
        </div>

        <ul class="pt-4 mt-4 space-y-2 font-medium border-t border-white dark:border-gray-700">
          <li class="font-medium text-center text-white dark:text-white">
            Version {Application.spec(:ex_nvr, :vsn)}
          </li>
        </ul>
      </div>
    </aside>
    """
  end

  attr(:items, :list, required: true)
  attr(:current_path, :string, default: nil)
  attr(:border, :boolean, default: false)

  defp sidebar_group(assigns) do
    class =
      case assigns[:border] do
        true -> "pt-4 mt-4 border-t border-white dark:border-gray-700"
        _ -> ""
      end

    assigns = assign(assigns, :class, class)

    ~H"""
    <ul class={"space-y-2 font-medium #{@class}"}>
      <.sidebar_item
        :for={item <- @items}
        label={item.label}
        icon={item.icon}
        href={item[:href]}
        target={item[:target]}
        children={item[:children] || []}
        role={item[:role]}
        current_path={@current_path}
      />
    </ul>
    """
  end

  attr(:label, :string, required: true)
  attr(:icon, :string, required: true)
  attr(:href, :string, default: nil)
  attr(:target, :string, default: nil)
  attr(:children, :list, default: [])
  attr(:current_path, :string, default: nil)
  attr(:is_active, :boolean, default: false)
  attr(:role, :atom, default: nil)

  defp sidebar_item(assigns) do
    active? = active?(assigns.href, assigns.current_path)
    has_active_child = has_active_child?(assigns.children, assigns.current_path)

    assigns =
      assigns
      |> assign(:is_active, active?)
      |> assign(:has_active_child, has_active_child)
      |> assign(:link_classes, link_classes(active?))
      |> assign(:icon_classes, icon_classes(active?))
      |> assign(:menu_classes, menu_classes(has_active_child))

    ~H"""
    <li>
      <button
        :if={@children != []}
        type="button"
        class="flex items-center justify-between w-full p-2 text-white rounded-lg hover:bg-gray-500 dark:hover:bg-gray-700"
        aria-controls={"dropdown-#{@label}"}
        data-collapse-toggle={"dropdown-#{@label}"}
        aria-expanded={@has_active_child}
      >
        <div class="flex items-center">
          <.icon name={@icon} class="w-6 h-6 dark:text-gray-400" />
          <span class="flex-1 ml-3 whitespace-nowrap">{@label}</span>
        </div>
        <.icon name="hero-chevron-down-solid" class="w-6 h-6 dark:text-gray-400" />
      </button>
      <ul id={"dropdown-#{@label}"} class={@menu_classes}>
        <.sidebar_item
          :for={child <- @children}
          label={child[:label]}
          icon={child[:icon]}
          href={child[:href]}
          target={child[:target]}
          children={child[:children] || []}
          current_path={@current_path}
          role={child[:role]}
        />
      </ul>
      <.link :if={@children == []} href={@href} target={@target} class={@link_classes}>
        <.icon name={@icon} class={@icon_classes} />
        <span class="ml-3">{@label}</span>
      </.link>
    </li>
    """
  end

  if Application.compile_env(:ex_nvr, :nerves_routes) do
    defp groups do
      [
        [
          %{label: "Dashboard", icon: "hero-tv-solid", href: ~p"/dashboard"},
          %{label: "Recordings", icon: "hero-film-solid", href: ~p"/recordings"},
          %{
            label: "Events",
            icon: "hero-camera-solid",
            children: [
              %{label: "Generic Events", icon: "hero-code-bracket", href: ~p"/events/generic"},
              %{label: "Vehicle Plates", icon: "hero-truck-solid", href: ~p"/events/lpr"}
            ]
          }
        ],
        [
          %{label: "Devices", icon: "hero-video-camera-solid", href: ~p"/devices"},
          %{label: "Users", icon: "hero-users-solid", href: ~p"/users", role: :admin},
          %{
            label: "Onvif Discovery",
            icon: "hero-magnifying-glass-circle",
            href: ~p"/onvif-discovery",
            role: :admin
          }
        ],
        [
          %{
            label: "Remote Storages",
            icon: "hero-circle-stack-solid",
            href: ~p"/remote-storages",
            role: :admin
          },
          %{
            label: "Removable Storages",
            icon: "hero-server-solid",
            href: ~p"/removable-storage",
            role: :admin
          }
        ],
        [
          %{
            label: "System Settings",
            icon: "hero-cog-6-tooth-solid",
            href: ~p"/nerves/system-settings",
            role: :admin
          }
        ],
        [
          %{
            label: "Live Dashboard",
            icon: "hero-chart-bar-solid",
            href: ~p"/live-dashboard",
            target: "_blank"
          },
          %{
            label: "API Documentation",
            icon: "hero-document-solid",
            href: "/swagger.html",
            target: "_blank"
          },
          %{
            label: "GitHub",
            icon: "svg-github",
            href: "https://github.com/evercam/ex_nvr",
            target: "_blank"
          }
        ]
      ]
    end
  else
    defp groups do
      [
        [
          %{label: "Dashboard", icon: "hero-tv-solid", href: ~p"/dashboard"},
          %{label: "Recordings", icon: "hero-film-solid", href: ~p"/recordings"},
          %{
            label: "Events",
            icon: "hero-camera-solid",
            children: [
              %{label: "Generic Events", icon: "hero-code-bracket", href: ~p"/events/generic"},
              %{label: "Vehicle Plates", icon: "hero-truck-solid", href: ~p"/events/lpr"}
            ]
          }
        ],
        [
          %{label: "Devices", icon: "hero-video-camera-solid", href: ~p"/devices"},
          %{label: "Users", icon: "hero-users-solid", href: ~p"/users", role: :admin},
          %{
            label: "Onvif Discovery",
            icon: "hero-magnifying-glass-circle",
            href: ~p"/onvif-discovery",
            role: :admin
          }
        ],
        [
          %{
            label: "Remote Storages",
            icon: "hero-circle-stack-solid",
            href: ~p"/remote-storages",
            role: :admin
          },
          %{
            label: "Removable Storage",
            icon: "hero-server-solid",
            href: ~p"/removable-storage",
            role: :admin
          }
        ],
        [
          %{
            label: "Live Dashboard",
            icon: "hero-chart-bar-solid",
            href: ~p"/live-dashboard",
            target: "_blank"
          },
          %{
            label: "API Documentation",
            icon: "hero-document-solid",
            href: "/swagger.html",
            target: "_blank"
          },
          %{
            label: "GitHub",
            icon: "svg-github",
            href: "https://github.com/evercam/ex_nvr",
            target: "_blank"
          }
        ]
      ]
    end
  end

  defp filter_group_by_role(group, role) do
    Enum.reject(group, fn
      %{children: children} -> filter_group_by_role(children, role) == []
      item -> not is_nil(item[:role]) and item[:role] != role
    end)
  end

  defp active?(nil, _), do: false
  defp active?(_, nil), do: false
  defp active?(href, current_path), do: String.starts_with?(current_path, href)

  defp has_active_child?(children, current_path) do
    Enum.any?(children, fn child ->
      active?(child[:href], current_path)
    end)
  end

  defp link_classes(true = _active),
    do:
      "flex items-center p-2 text-white rounded-lg bg-opacity-10 dark:bg-opacity-10 bg-blue-600 dark:bg-blue-500 text-blue-600 dark:text-blue-500"

  defp link_classes(false = _active),
    do: "flex items-center p-2 text-white rounded-lg hover:bg-gray-500 dark:hover:bg-gray-700"

  defp icon_classes(true = _active), do: "w-6 h-6 text-blue-600 dark:text-blue-500"
  defp icon_classes(false = _active), do: "w-6 h-6 text-gray-400 dark:text-gray-400"

  defp menu_classes(true = _active), do: "py-2 space-y-2 px-2"
  defp menu_classes(false = _active), do: "py-2 space-y-2 hidden"
end
