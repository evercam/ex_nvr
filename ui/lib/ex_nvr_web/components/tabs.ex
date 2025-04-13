defmodule ExNVRWeb.Components.Tabs do
  use Phoenix.LiveComponent
  use Phoenix.Component

  attr :id, :string, required: true
  attr :active_tab, :string, default: nil
  attr :class, :string, default: ""

  attr :active_class, :string,
    default:
      "bg-blue-600 dark:bg-blue-500 text-blue-600 border-blue-600 dark:text-blue-500 dark:border-blue-500"

  attr :inactive_class, :string,
    default: "text-gray-900 text-white dark:text-white hover:bg-gray-500 dark:hover:bg-gray-700"

  attr :on_change, :any, default: nil

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
  end

  slot :tab_content, required: true do
    attr :for, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <.live_component
      module={__MODULE__}
      id={@id}
      active_tab={@active_tab}
      class={@class}
      active_class={@active_class}
      inactive_class={@inactive_class}
      on_change={@on_change}
      tab={@tab}
      tab_content={@tab_content}
    />
    """
  end

  def mount(socket) do
    {:ok, assign(socket, active_tab: nil)}
  end

  def update(%{id: id} = assigns, socket) do
    default_tab =
      case assigns[:tab] do
        [first_tab | _] -> first_tab.id
        _ -> nil
      end

    active_tab =
      case assigns[:active_tab] do
        nil -> socket.assigns[:active_tab] || default_tab
        tab -> tab
      end

    socket =
      socket
      |> assign(:id, id)
      |> assign(:class, assigns[:class] || "")
      |> assign(:active_class, assigns[:active_class])
      |> assign(:inactive_class, assigns[:inactive_class])
      |> assign(:on_change, assigns[:on_change])
      |> assign(:tab, assigns[:tab])
      |> assign(:tab_content, assigns[:tab_content])
      |> assign(:active_tab, active_tab)

    {:ok, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab_id}, socket) do
    socket = assign(socket, active_tab: tab_id)

    if socket.assigns[:on_change] do
      send(self(), {socket.assigns.on_change, %{tab: tab_id, id: socket.assigns.id}})
    end

    {:noreply, socket}
  end

  defp tab_classes(active, active_class, inactive_class) do
    base_classes =
      "inline-flex rounded-t-md font-medium dark:bg-opacity-10 bg-opacity-10 px-4 py-2 items-center justify-center group"

    if active do
      "#{base_classes} #{active_class}"
    else
      "#{base_classes} #{inactive_class}"
    end
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <div class="border-b border-gray-200 dark:border-gray-700">
        <ul class="flex flex-wrap -mb-px text-center text-gray-500 dark:text-gray-400">
          <%= for tab <- @tab do %>
            <li
              id={"tab-" <> tab.id}
              class="me-2"
              aria-selected={
                if tab.id == @active_tab do
                  "true"
                else
                  "false"
                end
              }
            >
              <.link
                phx-click="switch_tab"
                phx-value-tab={tab.id}
                phx-target={@myself}
                class={tab_classes(tab.id == @active_tab, @active_class, @inactive_class)}
              >
                {tab.label}
              </.link>
            </li>
          <% end %>
        </ul>
      </div>
      <div class="py-4 px-8">
        <%= for content <- @tab_content do %>
          <%= if content.for == @active_tab do %>
            {render_slot(content)}
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end
end
