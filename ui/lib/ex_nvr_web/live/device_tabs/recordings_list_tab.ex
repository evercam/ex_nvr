defmodule ExNVRWeb.DeviceTabs.RecordingsListTab do
  @moduledoc """
    recordings list tab
      recordings list
      filters
      pagination
  """
  use ExNVRWeb, :live_component

  require Logger

  import ExNVRWeb.RecordingListLive, only: [recording_details_popover: 1]
  import ExNVRWeb.ViewUtils, only: [humanize_duration: 1]

  alias ExNVR.Recordings
  alias ExNVRWeb.RecordingListLive
  alias ExNVRWeb.Router.Helpers, as: Routes

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div
        class="text-center text-gray-500 dark:text-gray-400"
        id="recordings-tab"
        phx-hook="FlowbiteInit"
      >
        <div class="flex justify-between items-end mb-2">
          <.filter_form
            meta={@meta}
            recordings={@recordings}
            target={@myself}
            id="recording-filter-form"
          />
          <.pagination meta={@meta} target={@myself} />
        </div>

        <div>
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
            <:col :let={recording} label="Duration">
              {humanize_duration(
                DateTime.diff(recording.end_date, recording.start_date, :millisecond)
              )}
            </:col>
            <:action :let={recording}>
              <div class="flex justify-end">
                <button
                  data-popover-target={"popover-click-#{recording.id}"}
                  data-popover-trigger="click"
                  phx-click="fetch-details"
                  phx-value-id={recording.id}
                  type="button"
                  phx-target={@myself}
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
                  file_details={@files_details}
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
        </div>
      </div>
      <!-- Video Modal -->
      <div
        id="popup-container"
        class="popup-container fixed inset-0 z-50 hidden flex items-center justify-center p-4"
      >
        <div
          class="absolute inset-0 bg-black/80 backdrop-blur-sm"
          phx-click={RecordingListLive.close_popup()}
        >
        </div>
        <div class="relative z-10 w-full max-w-5xl bg-gray-900 rounded-2xl shadow-2xl overflow-hidden ring-1 ring-white/10">
          <div class="flex items-center justify-between px-5 py-3 bg-gray-800 border-b border-gray-700">
            <div class="flex items-center gap-2 min-w-0">
              <.icon name="hero-film-solid" class="w-5 h-5 text-blue-400 flex-shrink-0" />
              <p id="recording-modal-title" class="text-sm font-medium text-white truncate">
                Recording Preview
              </p>
            </div>
            <button
              class="ml-4 flex-shrink-0 text-gray-400 hover:text-white hover:bg-gray-700 rounded-lg p-1.5 transition-colors"
              phx-click={RecordingListLive.close_popup()}
              title="Close"
            >
              <.icon name="hero-x-mark-solid" class="w-5 h-5" />
            </button>
          </div>
          <div class="bg-black">
            <video id="recording-player" controls autoplay class="w-full max-h-[75vh] outline-none">
            </video>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def filter_form(%{meta: meta, recordings: recordings} = assigns) do
    assigns =
      assign(assigns, form: to_form(meta), meta: meta, recordings: recordings)

    ~H"""
    <div class="flex justify-between">
      <.form
        phx-taget={@target}
        for={@form}
        id={@id}
        phx-target={@target}
        phx-change="filter-recordings"
        class="flex items-baseline space-x-4"
      >
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
              class="border rounded p-1 "
              field={f.field}
              type={f.type}
              label={f.label}
              l_class="text-left"
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
  def update(assigns, socket) do
    params =
      if connected?(socket) && assigns.params["tab"] != "recordings" do
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
     |> assign(:filter_details, %{})
     |> assign_new(:pagination_params, fn -> %{} end)
     |> assign_new(:sort_params, fn -> %{} end)
     |> assign_new(:files_details, fn -> %{} end)
     |> assign_new(:filter_params, fn -> %{} end)
     |> assign_new(:recordings, fn -> %{} end)
     |> load_device_recordings(params)}
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

  defp load_device_recordings(socket, params) do
    next_page = Map.take(params, ["page"])

    sort_params =
      Map.take(params, ["order_by", "order_directions"])

    params = params["filter_params"] || sort_params || %{}

    nested_filter_params =
      nest_filter_params(socket, params, sort_params)
      |> Map.merge(next_page)

    case Recordings.list(nested_filter_params) do
      {:ok, {recordings, meta}} ->
        socket
        |> assign(meta: meta, recordings: recordings, sort_params: sort_params)

      {:error, meta} ->
        socket
        |> assign(meta: meta)
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
