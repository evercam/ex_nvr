defmodule ExNVRWeb.DeviceTabs.EventsListTab do
  @moduledoc """
    Events list tab
      events list tab
      filterers
      pagination
  """
  use ExNVRWeb, :live_component

  alias ExNVR.Events
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="flex justify-between items-end mb-4">
        <.event_filter_form meta={@meta} events={@events} target={@myself} />
        <.pagination meta={@meta} target={@myself} />
      </div>

      <div :if={@events == []} class="flex items-center justify-center py-24">
        <div class="text-center p-8 bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 rounded-xl shadow-sm">
          <div class="flex justify-center mb-4">
            <div class="flex items-center justify-center w-14 h-14 rounded-full bg-gray-100 dark:bg-gray-700">
              <svg
                class="w-7 h-7 text-gray-400 dark:text-gray-500"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="1.5"
                  d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
                />
              </svg>
            </div>
          </div>
          <h2 class="text-xl font-bold text-gray-900 dark:text-white mb-1">No Events Found</h2>
          <p class="text-gray-500 dark:text-gray-400 text-sm">
            No events match the current filters.
          </p>
        </div>
      </div>

      <div :if={@events != []} id="events-tab">
        <Flop.Phoenix.table
          id="events-table"
          opts={ExNVRWeb.FlopConfig.table_opts()}
          items={@events}
          meta={@meta}
          target={@myself}
          path={~p"/devices/#{@device.id}/details?tab=events"}
        >
          <:col :let={event} label="Device" field={:device_name}>
            {if event.device, do: event.device.name, else: "N/A"}
          </:col>
          <:col :let={event} label="Event Type" field={:type}>
            {event.type}
          </:col>
          <:col :let={event} label="Event Time" field={:time}>
            {Calendar.strftime(event.time, "%b %d, %Y %H:%M:%S %Z")}
          </:col>
          <:col :let={event} label="Data">
            {Jason.encode!(event.metadata)}
          </:col>
        </Flop.Phoenix.table>
      </div>
    </div>
    """
  end

  def event_filter_form(%{meta: meta, events: events} = assigns) do
    assigns = assign(assigns, form: to_form(meta), events: events)

    ~H"""
    <.form
      phx-target={@target}
      for={@form}
      id="event-tab-filter-form"
      phx-change="filter-events"
      class="flex items-end gap-4"
    >
      <Flop.Phoenix.filter_fields
        :let={f}
        form={@form}
        fields={[
          type: [op: :like, placeholder: "e.g. motion", label: "Event Type"],
          time: [op: :>=, type: "datetime-local", label: "From"],
          time: [op: :<=, type: "datetime-local", label: "To"]
        ]}
      >
        <div>
          <.input
            field={f.field}
            label={f.label}
            type={f.type}
            l_class="text-left"
            phx-debounce="500"
            {f.rest}
          />
        </div>
      </Flop.Phoenix.filter_fields>
    </.form>
    """
  end

  @impl true
  def update(assigns, socket) do
    params =
      if connected?(socket) && assigns.params["tab"] != "events" do
        assigns.params
        |> Map.put("filter_params", %{})
        |> Map.put("order_by", [])
        |> Map.put("order_direction", [])
      else
        assigns.params
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:pagination_params, fn -> %{} end)
     |> load_events(params)}
  end

  @impl true
  def handle_event("paginate", pagination_params, socket) do
    pagination_params = Map.merge(socket.assigns.pagination_params, pagination_params)

    params =
      Map.merge(socket.assigns.filter_params, pagination_params)
      |> Map.merge(socket.assigns.sort_params)

    {:noreply,
     socket
     |> assign(pagination_params: pagination_params)
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params),
       replace: true
     )}
  end

  @impl true
  def handle_event("filter-events", filter_params, socket) do
    params = Map.put(socket.assigns.params, "filter_params", filter_params)

    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:pagination_params, %{})
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
     )}
  end

  defp load_events(socket, params) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    params = params["filter_params"] || sort_params || %{}

    nest_event_filter_params =
      nest_filter_params(socket, params, sort_params)

    case Events.list_events(nest_event_filter_params) do
      {:ok, {events, meta}} ->
        assign(socket, meta: meta, events: events, sort_params: sort_params)

      {:error, meta} ->
        assign(socket, meta: meta, events: [])
    end
  end

  def nest_filter_params(socket, params, sort_params) do
    Flop.nest_filters(%{device_id: socket.assigns.device.id, filters: params["filters"]}, [
      :device_id
    ])
    |> then(fn filter ->
      params
      |> Map.put("filters", filter.filters)
      |> Map.merge(sort_params)
    end)
  end
end
