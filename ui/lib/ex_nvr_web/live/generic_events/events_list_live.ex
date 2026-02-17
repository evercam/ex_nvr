defmodule ExNVRWeb.GenericEventsLive.EventsList do
  use ExNVRWeb, :live_component

  alias ExNVR.Events
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H'''
    <div id="events-list" class="grow">
      <%= if assigns[:meta] do %>
        <div class="flex justify-between -ml-4 mt-3">
          <.form
            for={to_form(assigns.meta)}
            id="fitlers-form"
            phx-target={@myself}
            phx-change="filter-events"
            class="flex items-baseline space-x-4"
          >
            <Flop.Phoenix.filter_fields
              :let={f}
              form={to_form(assigns.meta)}
              fields={[
                device_id: [
                  type: "select",
                  options: @devices,
                  prompt: "Choose your device"
                ],
                type: [op: :like, placeholder: "Filter by event type"],
                time: [op: :>=, label: "Min event time"],
                time: [op: :<=, label: "Max event time"]
              ]}
            >
              <div>
                <.input
                  class="border rounded p-1"
                  field={f.field}
                  label={f.label}
                  type={f.type}
                  phx-debounce="500"
                  {f.rest}
                />
              </div>
            </Flop.Phoenix.filter_fields>
          </.form>
        </div>
        <Flop.Phoenix.table
          id="events"
          opts={ExNVRWeb.FlopConfig.table_opts()}
          items={@events}
          meta={@meta}
          path={~p"/events/generic"}
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

        <.pagination meta={@meta} target={@myself} />
      <% else %>
        <p class="text-center my-8 text-gray-500 dark:text-gray-400">
          Loading events...
        </p>
      <% end %>
    </div>
    '''
  end

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:pagination_params, fn -> %{} end)
     |> assign_new(:filter_params, fn -> %{} end)
     |> load_events(assigns.params)}
  end

  @impl true
  def handle_event("filter-events", filter_params, socket) do
    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> push_patch(to: Routes.generic_events_path(socket, :index, filter_params))}
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
     |> push_patch(to: Routes.generic_events_path(socket, :index, params), replace: true)}
  end

  defp load_events(socket, params) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    case Events.list_events(params) do
      {:ok, {events, meta}} ->
        assign(socket, meta: meta, events: events, sort_params: sort_params)

      {:error, meta} ->
        assign(socket, meta: meta, events: [])
    end
  end
end
