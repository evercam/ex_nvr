defmodule ExNVRWeb.RecordingListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVRWeb.Router.Helpers, as: Routes
  alias ExNVR.{Recordings, Devices}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow mt-20">
      <.filter_form meta={@meta} devices={@devices} id="recording-filter-form" />

      <Flop.Phoenix.table
        id="recordings"
        opts={ExNVRWeb.FlopConfig.table_opts()}
        items={@recordings}
        meta={@meta}
        path={~p"/recordings"}
      >
        <:col :let={recording} label="Id" field={:id}><%= recording.id %></:col>
        <:col :let={recording} label="Device" field={:device_name}><%= recording.device_name %></:col>
        <:col :let={recording} label="Start-date" field={:start_date}>
          <%= format_date(recording.start_date, recording.timezone) %>
        </:col>
        <:col :let={recording} label="End-date" field={:end_date}>
          <%= format_date(recording.end_date, recording.timezone) %>
        </:col>
        <:action :let={recording}>
          <div class="flex justify-end">
            <span
              title="Preview recording"
              phx-click={open_popup(recording)}
              id={"thumbnail-#{recording.id}"}
            >
              <.icon
                name="hero-eye-solid"
                class="w-6 h-6 z-auto mr-2 dark:text-gray-400 cursor-pointer thumbnail"
              />
            </span>
            <div class="flex justify-end">
              <.link
                href={~p"/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"}
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
    <!-- Popup container -->
    <div
      id="popup-container"
      class="popup-container fixed top-0 left-0 w-full h-full bg-black bg-opacity-75 flex justify-center items-center hidden"
    >
      <button class="popup-close absolute top-4 right-4 text-white" phx-click={close_popup()}>
        ×
      </button>
      <video id="recording-player" autoplay class="w-full h-auto max-w-full max-h-[80%]"></video>
    </div>
    """
  end

  def filter_form(%{meta: meta, devices: devices} = assigns) do
    assigns = assign(assigns, form: to_form(meta), meta: meta, devices: devices)

    ~H"""
    <div class="flex justify-between">
      <.form for={@form} id={@id} phx-change="filter-recordings" class="flex items-baseline space-x-4">
        <Flop.Phoenix.filter_fields
          :let={f}
          form={@form}
          fields={[
            device_id: [
              op: :==,
              type: "select",
              options: Enum.map(@devices, &{&1.name, &1.id}),
              prompt: "Choose your device",
              label: "Device"
            ],
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
    </div>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    Recordings.subscribe_to_recording_events()

    {:ok,
     assign(socket,
       devices: Devices.list(),
       filter_params: params,
       pagination_params: %{},
       sort_params: %{}
     )}
  end

  @impl true
  def handle_info(_msg, socket) do
    params =
      Map.merge(socket.assigns.filter_params, socket.assigns.pagination_params)
      |> Map.merge(socket.assigns.sort_params)

    load_recordings(params, socket)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    load_recordings(params, socket)
  end

  @impl true
  def handle_event("filter-recordings", filter_params, socket) do
    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:pagination_params, %{})
     |> push_patch(to: Routes.recording_list_path(socket, :list, filter_params))}
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
     |> push_patch(to: Routes.recording_list_path(socket, :list, params))}
  end

  defp load_recordings(params, socket) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    case Recordings.list(params) do
      {:ok, {recordings, meta}} ->
        {:noreply, assign(socket, meta: meta, recordings: recordings, sort_params: sort_params)}

      {:error, meta} ->
        {:noreply, assign(socket, meta: meta)}
    end
  end

  defp open_popup(recording) do
    JS.remove_class("hidden", to: "#popup-container")
    |> JS.set_attribute(
      {"src", "/api/devices/#{recording.device_id}/recordings/#{recording.filename}/blob"},
      to: "#recording-player"
    )
  end

  defp close_popup() do
    JS.add_class("hidden", to: "#popup-container")
    |> JS.set_attribute({"src", nil}, to: "#recording-player")
  end

  defp format_date(date, timezone) do
    date
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y %H:%M:%S")
  end
end
