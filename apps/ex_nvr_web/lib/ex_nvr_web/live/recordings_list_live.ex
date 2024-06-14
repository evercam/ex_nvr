defmodule ExNVRWeb.RecordingListLive do
  @moduledoc false

  require Logger
  use ExNVRWeb, :live_view

  import ExNVRWeb.ViewUtils

  alias ExNVRWeb.Router.Helpers, as: Routes
  alias ExNVR.{Recordings, Devices}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow">
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

  def recording_details_popover(%{rec_details: rec_details} = assigns) do
    assigns =
      if rec_details && rec_details != :error,
        do:
          assign(
            assigns,
            :video_track,
            Enum.find(rec_details.track_details, &(&1.type == :video))
          ),
        else: assigns

    ~H"""
    <div
      data-popover
      id={"popover-click-#{@recording.id}"}
      role="tooltip"
      class="absolute z-10 invisible inline-block w-64 text-sm text-gray-500 transition-opacity duration-300 bg-white border border-gray-200 rounded-lg shadow-sm opacity-0 dark:text-gray-400 dark:border-gray-600 dark:bg-gray-800"
    >
      <div class="px-3 py-2 bg-gray-100 border-b border-gray-200 rounded-t-lg dark:border-gray-600 dark:bg-gray-700">
        <h3 class="font-semibold text-gray-900 dark:text-white">Recording Details</h3>
      </div>
      <div :if={@rec_details && @rec_details != :error} class="px-3 py-2 grid">
        <p class="text-left text-sm font-bold dark:text-white">General</p>
        <table class="ml-3 mb-3 text-left text-xs">
          <tr>
            <td class="font-semibold">Size:</td>
            <td><%= humanize_size(@rec_details.size) %></td>
          </tr>
          <tr>
            <td class="font-semibold">Duration:</td>
            <td><%= humanize_duration(@rec_details.duration) %></td>
          </tr>
        </table>
        <p :if={@video_track} class="text-left text-sm font-bold dark:text-white">Video</p>
        <table class="ml-3 text-left text-xs">
          <tr>
            <td class="font-semibold">Codec:</td>
            <td><%= @video_track.codec %> (<%= @video_track.codec_tag %>)</td>
          </tr>
          <tr>
            <td class="font-semibold">Resolution:</td>
            <td><%= @video_track.width %> x <%= @video_track.height %></td>
          </tr>
          <tr>
            <td class="font-semibold">Bitrate:</td>
            <td><%= humanize_bitrate(@video_track.bitrate) %></td>
          </tr>
          <tr>
            <td class="font-semibold">fps:</td>
            <td><%= @video_track.fps %></td>
          </tr>
        </table>
      </div>
      <p :if={@rec_details == :error} class="px-3 py-2 text-red-500">
        Error while fetching details of the recording (the file may not exists)
      </p>
      <div data-popper-arrow></div>
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
       sort_params: %{},
       files_details: %{}
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
     |> push_patch(to: Routes.recording_list_path(socket, :list, params), replace: true)}
  end

  @impl true
  def handle_event("fetch-details", %{"id" => recording_id}, socket) do
    files_details = socket.assigns.files_details
    recording_id = String.to_integer(recording_id)
    recording = Enum.find(socket.assigns.recordings, &(&1.id == recording_id))
    device = Enum.find(socket.assigns.devices, &(&1.id == recording.device_id))

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

  defp load_recordings(params, socket) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    case Recordings.list(params) do
      {:ok, {recordings, meta}} ->
        socket
        |> assign(meta: meta, recordings: recordings, sort_params: sort_params)
        |> push_event("reload-popovers", %{})
        |> then(&{:noreply, &1})

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
    |> Calendar.strftime("%b %d, %Y %H:%M:%S %Z")
  end
end
