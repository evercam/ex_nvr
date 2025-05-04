defmodule ExNVRWeb.Components.Sidebar do
  use ExNVRWeb, :live_view

  attr :current_user, :map, required: true
  def sidebar(assigns) do
    ~H"""
    <aside
      id="logo-sidebar"
      class="fixed top-0 left-0 z-40 w-64 h-screen pt-20 transition-transform -translate-x-full bg-zinc-900 border-r border-white sm:translate-x-0 dark:bg-gray-800 dark:border-gray-700"
      aria-label="Sidebar"
    >
      <div class="flex flex-col justify-between h-full px-3 pb-4 overflow-y-auto bg-zinc-900 dark:bg-gray-800">
        <div>
          <%= for {group, index} <- Enum.with_index(groups()) do %>
            <.sidebar_group
              items={group}
              current_user={@current_user}
              border={index > 0}
            />
          <% end %>
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

  attr :items, :list, required: true
  attr :current_user, :map, required: true
  attr :border, :boolean, default: false
  defp sidebar_group(assigns) do
    class = case assigns[:border] do
      true -> "pt-4 mt-4 border-t border-white dark:border-gray-700"
      _ -> ""
    end

    assigns = assign(assigns, :class, class)

    ~H"""
    <ul class={"space-y-2 font-medium #{@class}"}>
      <%= for item <- @items do %>
        <.sidebar_item
          label={item.label}
          icon={item.icon}
          href={item[:href]}
          target={item[:target]}
          children={item[:children] || []}
          role={item[:role]}
          current_user={@current_user}
        />
      <% end %>
    </ul>
    """
  end

  attr :label, :string, required: true
  attr :icon, :string, required: true
  attr :href, :string, default: nil
  attr :target, :string, default: nil
  attr :children, :list, default: []
  attr :current_user, :map, default: nil
  attr :role, :atom, default: nil
  defp sidebar_item(assigns) do
    ~H"""
    <%= if is_nil(@role) or (@current_user && @current_user.role == @role) do %>
      <li>
        <%= if @children != [] do %>
          <button
            type="button"
            class="flex items-center justify-between w-full p-2 text-white rounded-lg hover:bg-gray-500 dark:hover:bg-gray-700"
            aria-controls={"dropdown-#{@label}"}
            data-collapse-toggle={"dropdown-#{@label}"}
          >
            <div class="flex items-center">
              <.icon name={@icon} class="w-6 h-6 dark:text-gray-400" />
              <span class="flex-1 ml-3 whitespace-nowrap"><%= @label %></span>
            </div>
            <.icon name="hero-chevron-down-solid" class="w-6 h-6 dark:text-gray-400" />
          </button>
          <ul id={"dropdown-#{@label}"} class="hidden py-2 space-y-2">
            <%= for child <- @children do %>
              <.sidebar_item
                label={child[:label]}
                icon={child[:icon]}
                href={child[:href]}
                target={child[:target]}
                children={child[:children] || []}
                current_user={@current_user}
                role={child[:role]}
              />
            <% end %>
          </ul>
        <% else %>
          <.link
            href={@href}
            target={@target}
            class="flex items-center p-2 text-white rounded-lg hover:bg-gray-500 dark:hover:bg-gray-700"
          >
            <.icon name={@icon} class="w-6 h-6 dark:text-gray-400" />
            <span class="ml-3"><%= @label %></span>
          </.link>
        <% end %>
      </li>
    <% end %>
    """
  end

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
          href: ~p"/swagger/index.html",
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
