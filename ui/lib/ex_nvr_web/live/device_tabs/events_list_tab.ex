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
    ~H'''
    <div class="text-center text-gray-500 dark:text-gray-400">
      <.event_filter_form meta={@meta} events={@events} target={@myself} />
      <Flop.Phoenix.table
        id="events-tab"
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

      <.pagination meta={@meta} target={@myself} />
    </div>
    '''
  end

  def event_filter_form(%{meta: meta, events: events} = assigns) do
    assigns =
      assign(assigns, form: to_form(meta), events: events)

    ~H"""
    <.form
      phx-target={@target}
      for={@form}
      id="event-tab-filter-form"
      phx-change="filter-events"
      class="flex space-x-4"
    >
      <Flop.Phoenix.filter_fields
        :let={f}
        form={@form}
        fields={[
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
    """
  end

  @impl true
  def update(assigns, socket) do
    params =
      if connected?(socket) && assigns.params["tab"] != "events" do
        Map.put(assigns.params, "filter_params", %{})
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
