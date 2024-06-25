defmodule ExNVRWeb.LPREventsListLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVRWeb.Router.Helpers, as: Routes
  alias ExNVR.{Devices, Events}

  @default_plate_image_path "priv/static/images/no_plate_image.jpg"

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grow">
      <.filter_form meta={@meta} devices={@devices} id="lpr-event-filter-form" />
      <Flop.Phoenix.table
        id="events"
        opts={ExNVRWeb.FlopConfig.table_opts()}
        items={@events}
        meta={@meta}
        path={~p"/events/lpr"}
      >
        <:col :let={lpr_event} label="Plate image" field={:plate_image}>
          <img
            src={show_plate_image(lpr_event, @default_plate_image)}
            class="mx-auto w-[80%] h-auto max-w-[80%] max-h-[80%]"
          />
        </:col>
        <:col :let={lpr_event} label="Device" field={:device_name}><%= lpr_event.device.name %></:col>
        <:col :let={lpr_event} label="Capture time" field={:capture_time}>
          <%= format_date(lpr_event.capture_time, lpr_event.device.timezone) %>
        </:col>
        <:col :let={lpr_event} label="Plate number" field={:plate_number}>
          <%= lpr_event.plate_number %>
        </:col>
        <:col :let={lpr_event} label="Diection" field={:direction}>
          <%= uppercase_direction(lpr_event.direction) %>
        </:col>

        <:action :let={lpr_event}>
          <%!-- <div class="flex justify-end"> --%>
          <span
            title="Preview snapshot"
            phx-click={preview_event(lpr_event)}
            id={"thumbnail-#{lpr_event.id}"}
          >
            <.icon
              name="hero-eye-solid"
              class="w-6 h-6 z-auto mr-2 dark:text-gray-400 cursor-pointer thumbnail"
            />
          </span>
          <span
            title="Preview clip"
            phx-click={preview_event_clip(lpr_event)}
            id={"clip-#{lpr_event.id}"}
          >
            <.icon
              name="hero-video-camera-solid"
              class="w-6 h-6 z-auto mr-2 dark:text-gray-400 cursor-pointer"
            />
          </span>
          <%!-- </div> --%>
        </:action>
      </Flop.Phoenix.table>

      <.pagination meta={@meta} />
    </div>
    <!-- Popup container -->
    <div
      id="popup-container"
      class="popup-container fixed top-0 left-0 w-full h-full bg-black bg-opacity-75 flex justify-center items-center hidden"
    >
      <button
        class="popup-close absolute top-4 right-4 text-white"
        phx-click={JS.add_class("hidden", to: "#popup-container")}
      >
        ×
      </button>
      <img id="event-image" class="w-full h-auto max-w-full max-h-[80%]" />
    </div>
    <!-- Clip popup container -->
    <div
      id="clip-popup-container"
      class="popup-container fixed top-0 left-0 w-full h-full bg-black bg-opacity-75 flex justify-center items-center hidden"
    >
      <button class="popup-close absolute top-4 right-4 text-white" phx-click={close_clip_popup()}>
        ×
      </button>
      <video id="event-clip" autoplay controls class="w-full h-auto max-w-full max-h-[80%]" />
    </div>
    """
  end

  def filter_form(%{meta: meta, devices: devices} = assigns) do
    assigns = assign(assigns, form: to_form(meta), meta: meta, devices: devices)

    ~H"""
    <div class="flex justify-between">
      <.form for={@form} id={@id} phx-change="filter-events" class="flex items-baseline space-x-4">
        <Flop.Phoenix.filter_fields
          :let={f}
          form={@form}
          fields={[
            device_id: [
              type: "select",
              options: Enum.map(@devices, &{&1.name, &1.id}),
              prompt: "Choose your device"
            ],
            capture_time: [op: :>=, label: "Min capture time"],
            capture_time: [op: :<=, label: "Max capture time"],
            plate_number: [op: :like, placeholder: "Filter by plate number"]
          ]}
        >
          <div>
            <.input
              class="border rounded p-1 kiw"
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
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {:ok,
     assign(socket,
       devices: Devices.list(),
       default_plate_image: default_plate_image(),
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

    load_lpr_events(params, socket)
  end

  @impl true
  def handle_params(params, _uri, socket) do
    load_lpr_events(params, socket)
  end

  @impl true
  def handle_event("filter-events", filter_params, socket) do
    {:noreply,
     socket
     |> assign(:filter_params, filter_params)
     |> assign(:pagination_params, %{})
     |> push_patch(to: Routes.lpr_events_list_path(socket, :list, filter_params))}
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
     |> push_patch(to: Routes.lpr_events_list_path(socket, :list, params), replace: true)}
  end

  defp uppercase_direction(direction) do
    direction |> Atom.to_string() |> String.upcase()
  end

  defp load_lpr_events(params, socket) do
    sort_params = Map.take(params, ["order_by", "order_directions"])

    case Events.list_lpr_events(params) do
      {:ok, {events, meta}} ->
        {:noreply, assign(socket, meta: meta, events: events, sort_params: sort_params)}

      {:error, meta} ->
        {:noreply, assign(socket, meta: meta)}
    end
  end

  defp format_date(date, timezone) do
    date
    |> DateTime.shift_zone!(timezone)
    |> Calendar.strftime("%b %d, %Y %H:%M:%S %Z")
  end

  defp default_plate_image() do
    Application.app_dir(:ex_nvr_web)
    |> Path.join(@default_plate_image_path)
    |> File.read!()
    |> Base.encode64()
  end

  defp show_plate_image(lpr_event, default_plate_image) do
    plate_image = Events.lpr_event_thumbnail(lpr_event)

    if(plate_image) do
      "data:image/png;base64,#{plate_image}"
    else
      "data:image/png;base64,#{default_plate_image}"
    end
  end

  defp preview_event(lpr_event) do
    JS.remove_class("hidden", to: "#popup-container")
    |> JS.set_attribute(
      {"src",
       "/api/devices/#{lpr_event.device_id}/snapshot?time=#{lpr_event.capture_time}&method=precise"},
      to: "#event-image"
    )
  end

  defp preview_event_clip(lpr_event) do
    params = %{
      stream: :auto,
      pos: DateTime.add(lpr_event.capture_time, -5) |> DateTime.to_iso8601(),
      duration: 10
    }

    url = ~p"/api/devices/#{lpr_event.device_id}/hls/index.m3u8?#{params}"

    JS.remove_class("hidden", to: "#clip-popup-container")
    |> JS.dispatch("events:play-clip", to: "#event-clip", detail: %{src: url})
  end

  defp close_clip_popup() do
    JS.add_class("hidden", to: "#clip-popup-container")
    |> JS.set_attribute({"src", nil}, to: "#event-clip")
  end
end
