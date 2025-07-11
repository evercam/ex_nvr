defmodule ExNVRWeb.DeviceDetailsLive do
  use ExNVRWeb, :live_view

  require Logger

  import ExNVRWeb.RecordingListLive, only: [recording_details_popover: 1]

  alias ExNVR.{Devices, Recordings}
  alias ExNVRWeb.Router.Helpers, as: Routes
  alias ExNVRWeb.RecordingListLive

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
     |> load_device_recordings(params)}
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

  def load_device_recordings(socket, params) do
    sort_params =
      Map.take(params, ["order_by", "order_directions"])

    params = params["filter_params"] || sort_params || %{}

    case Recordings.get_recordings_by_device_id(socket.assigns.device.id, params) do
      {:ok, {recordings, meta}} ->
        socket
        |> assign(meta: meta, recordings: recordings, sort_params: sort_params)

      {:error, meta} ->
        socket
        |> assign(meta: meta)
    end
  end

  def filter_form(%{meta: meta, recordings: recordings} = assigns) do
    assigns =
      assign(assigns, form: to_form(meta), meta: meta, recordings: recordings)

    ~H"""
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

        <:tab_content for="details">
          <div class="space-y-2 text-black dark:text-white">
            <p><strong>Name:</strong> {@device.name}</p>
            <p><strong>Type:</strong> {Atom.to_string(@device.type)}</p>
            <p><strong>Status:</strong> {Atom.to_string(@device.state)}</p>
            <p>
              <strong>Created:</strong> {Calendar.strftime(
                @device.inserted_at,
                "%b %d, %Y %H:%M:%S %Z"
              )}
            </p>
            <p><strong>Timezone:</strong> {@device.timezone}</p>
            <div class="mt-4">
              <img src={~p"/api/devices/#{@device.id}/snapshot"} class="max-w-md" />
            </div>
          </div>
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

        <:tab_content for="stats">
          <div class="text-center text-gray-500 dark:text-gray-400">Stats tab coming soon...</div>
        </:tab_content>

        <:tab_content for="settings">
          <div class="text-center text-gray-500 dark:text-gray-400">Settings tab coming soon...</div>
        </:tab_content>

        <:tab_content for="events">
          <div class="text-center text-gray-500 dark:text-gray-400">Events tab coming soon...</div>
        </:tab_content>
      </.tabs>
    </div>
    """
  end
end
