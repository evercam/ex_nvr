defmodule ExNVRWeb.DeviceDetailsLive do
  use ExNVRWeb, :live_view

  require Logger

  import ExNVR.Authorization

  import ExNVRWeb.RecordingListLive, only: [recording_details_popover: 1]

  alias ExNVR.Events
  alias ExNVR.{Devices, Recordings}
  alias ExNVRWeb.RecordingListLive
  alias ExNVRWeb.Router.Helpers, as: Routes

  alias ExNVR.Model.Device

  @impl true
  def mount(%{"id" => device_id} = params, _session, socket) do
    device = Devices.get!(device_id)

    {:ok, {recordings, meta}} =
      Recordings.get_recordings_by_device_id(device_id)

    active_tab = params["tab"] || "details"

    {:ok,
     assign(socket,
       filter_params: %{},
       sort_params: %{},
       device: device,
       recordings: recordings,
       events: [],
       meta: meta,
       active_tab: active_tab,
       params: params,
       pagination_params: %{},
       files_details: %{}
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply,
     socket
     |> assign(:active_tab, params["tab"] || socket.assigns.active_tab)
     |> assign(:params, params)
     |> load_device_recordings_or_events(params)}
  end

  @impl true
  def handle_info({:tab_changed, %{tab: tab}}, socket) do
    params = Map.put(socket.assigns.params, "tab", tab)

    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
     )}
  end

  @impl true
  def handle_info(_msg, socket) do
    Map.merge(socket.assigns.filter_params, socket.assigns.pagination_params)
    |> Map.merge(socket.assigns.sort_params)
  end

  @impl true
  def handle_event("filter-recordings", filter_params, socket) do
    params = Map.put(socket.assigns.params, "filter_params", filter_params)

    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:pagination_params, %{})
     |> push_patch(
       to: Routes.device_details_path(socket, :show, socket.assigns.device.id, params)
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

  @impl true
  def handle_event("fetch-details", %{"id" => recording_id}, socket) do
    files_details = socket.assigns.files_details
    recording_id = String.to_integer(recording_id)
    recording = Enum.find(socket.assigns.recordings, &(&1.id == recording_id))
    device = socket.assigns.device

    files_details =
      with :error <- Map.fetch(files_details, recording_id),
           {:error, reason} <- Recordings.details(device, recording) do
        Logger.error("could not fetch file details, due to: #{inspect(reason)}")
        Map.put(files_details, recording_id, :error)
      else
        {:ok, details} -> Map.put(socket.assigns.files_details, recording_id, details)
      end

    {:noreply, assign(socket, :files_details, files_details)}
  end

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

  def handle_event("stop-recording", _params, socket) do
    user = socket.assigns.current_user

    case authorize(user, :device, :update) do
      :ok -> update_device_state(socket, :stopped)
      {:error, :unauthorized} -> unauthorized(socket, :noreply)
    end
  end

  def handle_event("start-recording", _params, socket) do
    user = socket.assigns.current_user

    Device.recording?(socket.assigns.device)

    case authorize(user, :device, :update) do
      :ok -> update_device_state(socket, :recording)
      {:error, :unauthorized} -> unauthorized(socket, :noreply)
    end
  end

  def handle_event("delete-device", socket) do
    user = socket.assigns.current_user
    device = socket.assigns.device

    with :ok <- authorize(user, :device, :delete),
         :ok <- Devices.delete(device) do
      socket =
        socket
        |> put_flash(:info, "Device #{device.name} Deleted")
        |> push_navigate(to: "/devices")

      {:noreply, socket}
    else
      _other -> {:noreply, put_flash(socket, :error, "could not delet device")}
    end
  end

  defp update_device_state(socket, new_state) do
    device =
      socket.assigns.device

    Devices.update_state(device, new_state)
    |> case do
      {:ok, device} ->
        {:noreply,
         socket
         |> assign(device: device)}

      _ ->
        {:noreply, put_flash(socket, :error, "could not update device state")}
    end
  end

  defp unauthorized(socket, reply) do
    socket
    |> put_flash(:error, "You are not authorized to perform this action!")
    |> then(&{reply, &1})
  end

  defp load_device_recordings_or_events(socket, params)
       when socket.assigns.active_tab == "recordings" do
    sort_params =
      Map.take(params, ["order_by", "order_directions"])

    params = params["filter_params"] || sort_params || %{}

    nested_filter_params = nest_filter_params(socket, params, sort_params)

    case Recordings.list(nested_filter_params) do
      {:ok, {recordings, meta}} ->
        socket
        |> assign(meta: meta, recordings: recordings, sort_params: sort_params)

      {:error, meta} ->
        socket
        |> assign(meta: meta)
    end
  end

  defp load_device_recordings_or_events(socket, params)
       when socket.assigns.active_tab == "events" do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    params = params["filter_params"] || sort_params || %{}

    nest_event_filter_params =
      nest_filter_params(socket, params, sort_params)

    Events.list_events(nest_event_filter_params)
    |> case do
      {:ok, {events, meta}} ->
        assign(socket, meta: meta, events: events, sort_params: sort_params)

      {:error, meta} ->
        assign(socket, meta: meta, events: [])
    end
  end

  defp load_device_recordings_or_events(socket, _params), do: socket

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

  def filter_form(%{meta: meta, recordings: recordings} = assigns) do
    assigns =
      assign(assigns, form: to_form(meta), meta: meta, recordings: recordings)

    ~H"""
    <div class="flex justify-between">
      <.form for={@form} id={@id} phx-change="filter-recordings" class="flex items-baseline space-x-4">
        <Flop.Phoenix.filter_fields
          :let={f}
          form={@form}
          fields={[
            start_date: [op: :>=, type: "datetime-local", label: "Start Date"],
            end_date: [op: :<=, type: "datetime-local", label: "End Date"]
          ]}
        >
          <div>
            <.input
              class="border rounded p-1"
              field={f.field}
              type={f.type}
              label={f.label}
              phx-debounce="500"
              {f.rest}
            />
          </div>
        </Flop.Phoenix.filter_fields>
      </.form>
    </div>
    """
  end

  def event_filter_form(%{meta: meta, events: events} = assigns) do
    assigns =
      assign(assigns, form: to_form(meta), events: events)

    ~H"""
    <.form for={@form} id="event-tab-filter-form" phx-change="filter-events" class="flex space-x-4">
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
  def render(assigns) do
    ~H"""
    <div class="grow px-4 py-6">
      <h2 class="text-xl font-semibold text-black dark:text-white mb-4">
        Device: {@device.name}
      </h2>
      <.tabs id="device-details-tabs" active_tab={@active_tab} on_change={:tab_changed}>
        <:tab id="details" label="Details" />
        <:tab id="recordings" label="Recordings" />
        <:tab id="stats" label="Stats" />
        <:tab id="settings" label="Settings" />
        <:tab id="events" label="Events" />
        
    <!-- device details tab -->
        <:tab_content for="details">
          <ul class="divide-y divide-gray-700 text-white rounded-md shadow-sm max-w-xl ">
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Name:</span>
              <span>{@device.name}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Type:</span>
              <span>{@device.type}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Status:</span>
              <span class="font-bold flex items-center gap-1">
                <div class={
                  ["h-2.5 w-2.5 rounded-full mr-2"] ++
                    case @device.state do
                      :recording -> ["bg-green-500"]
                      :streaming -> ["bg-green-500"]
                      :failed -> ["bg-red-500"]
                      :stopped -> ["bg-yellow-500"]
                    end
                }>
                </div>
                {String.upcase(to_string(@device.state))}
              </span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Created At:</span>
              <span>{Calendar.strftime(@device.inserted_at, "%b %d, %Y %H:%M:%S %Z")}</span>
            </li>
            <li class="p-4 flex justify-between items-center">
              <span class="font-semibold text-gray-400">Timezone:</span>
              <span>{@device.timezone}</span>
            </li>
          </ul>
        </:tab_content>
        
    <!-- recordings tab -->
        <:tab_content for="recordings">
          <div class="text-center text-gray-500 dark:text-gray-400">
            <.filter_form meta={@meta} recordings={@recordings} id="recording-filter-form" />

            <Flop.Phoenix.table
              id="recordings"
              opts={ExNVRWeb.FlopConfig.table_opts()}
              meta={@meta}
              items={@recordings}
              path={~p"/devices/#{@device.id}/details?tab=recordings"}
            >
              <:col :let={recording} label="Id">{recording.id}</:col>
              <:col :let={recording} label="Start-date" field={:start_date}>
                {RecordingListLive.format_date(recording.start_date, @device.timezone)}
              </:col>
              <:col :let={recording} label="End-date" field={:end_date}>
                {RecordingListLive.format_date(recording.end_date, @device.timezone)}
              </:col>
              <:action :let={recording}>
                <div class="flex justify-end">
                  <button
                    data-popover-target={"popover-click-#{recording.id}"}
                    data-popover-trigger="click"
                    phx-click="fetch-details"
                    phx-value-id={recording.id}
                    type="button"
                  >
                    <span title="Show information">
                      <.icon
                        name="hero-information-circle-solid"
                        class="w-6 h-6 mr-2 dark:text-gray-400 cursor-pointer"
                      />
                    </span>
                  </button>
                  <.recording_details_popover
                    recording={recording}
                    rec_details={@files_details[recording.id]}
                  />
                  <span
                    title="Preview recording"
                    phx-click={RecordingListLive.open_popup(recording)}
                    id={"thumbnail-#{recording.id}"}
                  >
                    <.icon
                      name="hero-eye-solid"
                      class="w-6 h-6 z-auto mr-2 dark:text-gray-400 cursor-pointer thumbnail"
                    />
                  </span>
                  <div class="flex justify-end">
                    <.link
                      href={
                        ~p"/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"
                      }
                      class="inline-flex items-center text-gray-900 rounded-lg"
                      id={"recording-#{recording.id}-link"}
                    >
                      <span title="Download recording">
                        <.icon name="hero-arrow-down-tray-solid" class="w-6 h-6 dark:text-gray-400" />
                      </span>
                    </.link>
                  </div>
                </div>
              </:action>
            </Flop.Phoenix.table>

            <.pagination meta={@meta} />
          </div>
          <div
            id="popup-container"
            class="popup-container fixed top-0 left-0 w-full h-full bg-black bg-opacity-75 flex justify-center items-center hidden"
          >
            <button
              class="popup-close absolute top-4 right-4 text-white"
              phx-click={RecordingListLive.close_popup()}
            >
              ×
            </button>
            <video id="recording-player" autoplay class="w-full h-auto max-w-full max-h-[80%]">
            </video>
          </div>
        </:tab_content>
        
    <!-- stats tab-->
        <:tab_content for="stats">
          <div class="text-center text-gray-500 dark:text-gray-400">Stats tab coming soon...</div>
        </:tab_content>

        <:tab_content for="settings">
          <div class="text-center text-gray-500 dark:text-gray-400">
            Settings tab comming soon....
          </div>
        </:tab_content>
        
    <!-- events tab-->
        <:tab_content for="events">
          <div class="text-center text-gray-500 dark:text-gray-400">
            <.event_filter_form meta={@meta} events={@events} />

            <Flop.Phoenix.table
              id="events"
              opts={ExNVRWeb.FlopConfig.table_opts()}
              items={@events}
              meta={@meta}
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

            <.pagination meta={@meta} />
          </div>
        </:tab_content>
      </.tabs>
    </div>
    """
  end
end
