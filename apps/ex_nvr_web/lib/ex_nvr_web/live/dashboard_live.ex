defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view
  alias ExNVRWeb.TimelineComponent

  alias ExNVR.Devices
  alias ExNVR.Recordings
  alias ExNVR.Model.Device

  def render(assigns) do
    ~H"""
    <div class="bg-white sm:w-2/3 dark:bg-gray-800">
      <%!-- <div class="hidden" id="alert-container">
        <div class="bg-white rounded-md p-4 shadow-md">
          <button id="close-alert" class="absolute top-2 right-2 text-gray-400 hover:text-gray-600">
            <svg
              class="w-4 h-4"
              fill="none"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path d="M6 18L18 6M6 6l12 12"></path>
            </svg>
          </button>
          <img id="alert-image" class="w-24 h-24 mx-auto mb-2" src="" alt="Alert Image" />
          <p id="alert-label" class="text-center text-gray-800"></p>
        </div>
      </div> --%>

      <div :if={@devices == []} class="grid tracking-wide text-lg text-center dark:text-gray-200">
        You have no devices, you can create one
        <span><.link href={~p"/devices"} class="ml-2 dark:text-blue-600">here</.link></span>
      </div>
      <div :if={@devices != []}>
        <div class="flex items-center justify-between invisible sm:visible">
          <.simple_form for={@form} id="device_form">
            <div class="flex items-center">
              <div class="mr-4">
                <.input
                  field={@form[:device]}
                  id="device_form_id"
                  type="select"
                  label="Device"
                  options={Enum.map(@devices, &{&1.name, &1.id})}
                  phx-change="switch_device"
                />
              </div>

              <div class={[@start_date && "hidden"]}>
                <.input
                  field={@form[:stream]}
                  type="select"
                  label="Stream"
                  options={@supported_streams}
                  phx-change="switch_stream"
                />
              </div>
            </div>
          </.simple_form>
        </div>

        <div class="relative mt-4">
          <div :if={@live_view_enabled?} class="relative">
            <video
              id="live-video"
              class="w-full h-auto dark:bg-gray-500 rounded-tr rounded-tl"
              autoplay
              controls
              muted
            />
          </div>
          <div
            :if={not @live_view_enabled?}
            class="relative text-lg rounded-tr rounded-tl text-center dark:text-gray-200 mt-4 w-full dark:bg-gray-500 h-96 flex justify-center items-center d-flex"
          >
            Device is not recording, live view is not available
          </div>
          <.live_component
            module={TimelineComponent}
            id="tl"
            segments={@segments}
            timezone={@timezone}
          />
        </div>
      </div>

      <div id="detection-container" class="text-center text-green-500">
        <div class="mb-4">
          <h2 class="text-xl font-bold">Image Detected: </h2>
        </div>
        <img id="alert-image" class="w-224 h-224 mx-auto mb-2" src={@detection_img} alt="Alert Image" />
        <div class="mb-4">
          <h2 class="text-xl font-bold"> Prediction: </h2>
        </div>
        <div class="bg-white inline-block px-2">
          <p><%= @detection_label %></p>
        </div>
      </div>
    </div>
    """
  end

  @spec mount(any, any, Phoenix.LiveView.Socket.t()) :: {:ok, any}
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_devices()
      |> assign_current_device()
      |> assign_streams()
      |> assign_form(nil)
      |> assign_start_date(nil)
      |> live_view_enabled?()
      |> assign_runs()
      |> assign_timezone()
      |> maybe_push_stream_event(nil)

      if connected?(socket) do
        Enum.each(socket.assigns.devices, fn device -> Phoenix.PubSub.subscribe(ExNVR.PubSub, "detection-#{device.id}") end)
      end

    {:ok, assign(socket, start_date: nil, detection_label: "", detection_img: "")}
  end

  def handle_info({:prediction, prediction, current_encoded_frame, _device_id}, socket) do
    # IO.inspect("LIVE VIEW ===== prediction Event!!!!! #{prediction} ")
    # push_event(socket, "show_alert", %{image: current_encoded_frame, label: prediction})
    # {:noreply, socket}
    # if socket.current_device and socket.current_device.id == device_id do
    new_socket = assign(socket, detection_label: prediction, detection_img: "data:image/jpeg;base64, #{current_encoded_frame}")
    {:noreply, new_socket}

    # else
    #   {:noreply, socket}
    # end

  end

  def handle_event("switch_device", %{"device" => device_id}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    socket =
      socket
      |> assign_current_device(device)
      |> assign_streams()
      |> assign_form(nil)
      |> live_view_enabled?()
      |> assign_runs()
      |> assign_timezone()
      |> maybe_push_stream_event(socket.assigns.start_date)

    {:noreply, socket}
  end

  def handle_event("switch_stream", %{"stream" => stream}, socket) do
    socket =
      socket
      |> assign_form(%{"stream" => stream, "device" => socket.assigns.current_device.id})
      |> live_view_enabled?()
      |> maybe_push_stream_event(socket.assigns.start_date)

    {:noreply, socket}
  end

  def handle_event("datetime", %{"value" => value}, socket) do
    current_datetime = socket.assigns.start_date
    new_datetime = parse_datetime(value)

    socket =
      if current_datetime != new_datetime do
        socket
        |> assign_start_date(new_datetime)
        |> live_view_enabled?()
        |> maybe_push_stream_event(new_datetime)
      else
        socket
      end

    {:noreply, socket}
  end

  defp assign_devices(socket) do
    assign(socket, devices: Devices.list())
  end

  defp assign_current_device(socket, device \\ nil) do
    devices = socket.assigns.devices
    assign(socket, current_device: device || List.first(devices))
  end

  defp assign_start_date(socket, start_date), do: assign(socket, start_date: start_date)

  defp assign_streams(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_streams(socket) do
    device = socket.assigns.current_device

    supported_streams =
      if Device.has_sub_stream(device) do
        [{"Main Stream", "main_stream"}, {"Sub Stream", "sub_stream"}]
      else
        [{"Main Stream", "main_stream"}]
      end

    assign(socket, supported_streams: supported_streams)
  end

  defp assign_runs(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_runs(socket) do
    device = socket.assigns.current_device

    segments =
      Recordings.list_runs(%{device_id: device.id})
      |> Enum.map(&Map.take(&1, [:start_date, :end_date]))
      |> Jason.encode!()

    assign(socket, segments: segments)
  end

  defp assign_timezone(%{assigns: %{current_device: nil}} = socket), do: socket

  defp assign_timezone(socket) do
    assign(socket, timezone: socket.assigns.current_device.timezone)
  end

  defp assign_form(%{assigns: %{current_device: nil}} = socket, _params), do: socket

  defp assign_form(socket, nil) do
    device = socket.assigns.current_device
    assign(socket, form: to_form(%{"device" => device.id, "stream" => "main_stream"}))
  end

  defp assign_form(socket, params) do
    assign(socket, form: to_form(params))
  end

  defp maybe_push_stream_event(socket, datetime) do
    cond do
      not connected?(socket) ->
        socket

      not socket.assigns.live_view_enabled? ->
        socket

      true ->
        device = socket.assigns.current_device
        current_stream = if socket.assigns.form.params["stream"] == "main_stream", do: 0, else: 1

        {stream_url, poster_url} = stream_url(device, datetime, current_stream)

        push_event(socket, "stream", %{src: stream_url, poster: poster_url})
    end
  end

  defp live_view_enabled?(socket) do
    device = socket.assigns.current_device
    start_date = socket.assigns[:start_date]

    enabled? =
      cond do
        is_nil(device) -> false
        not is_nil(start_date) -> true
        not ExNVR.Utils.run_main_pipeline?() -> false
        device.state == :recording -> true
        true -> false
      end

    assign(socket, live_view_enabled?: enabled?)
  end

  defp parse_datetime(datetime) do
    case DateTime.from_iso8601(datetime <> ":00Z") do
      {:ok, date, _} -> date
      _ -> nil
    end
  end

  defp stream_url(device, datetime, current_stream) do
    stream_url =
      ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: format_date(datetime), stream: current_stream}}"

    if datetime do
      poster_url = ~p"/api/devices/#{device.id}/snapshot?#{%{time: format_date(datetime)}}"
      {stream_url, poster_url}
    else
      {stream_url, nil}
    end
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)
end
