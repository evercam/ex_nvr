defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view
  alias ExNVRWeb.TimelineComponent

  alias ExNVR.Devices
  alias ExNVR.Recordings
  alias ExNVR.Model.Device

  def render(assigns) do
    ~H"""
    <div class="bg-white sm:w-2/3 dark:bg-gray-800">
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

          <div class="mt-20 mb-2">
            <.button id="download-footage-btn" class="bg-blue-500 text-white px-4 py-2 rounded flex items-center" phx-click="show_footage_popup">
              <span title="Download footage" class="mr-2">
                <svg xmlns="http://www.w3.org/2000/svg" class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3"/>
                </svg>
              </span>
              Download
            </.button>
          </div>
          <%= if @show_footage_popup do %>
            <div class="fixed inset-0 flex items-center justify-center z-50">
              <div class="bg-white dark:bg-gray-800 p-8 rounded w-96 border">
                <h2 class="text-xl text-white font-bold mb-4">Download Footage</h2>
                <.simple_form for={@footage_form} id="footage_form" class="w-full space-y-4" phx-submit="download_footage">
                  <div class="space-y-2">
                    <div class="mr-4 w-full p-2 rounded">
                      <.input
                        field={@footage_form[:device]}
                        id="footage_device_id"
                        type="select"
                        label="Device"
                        options={Enum.map(@devices, &{&1.name, &1.id})}
                        required
                      />
                    </div>
                    <div class="mr-4 w-full p-2 rounded">
                      <.input
                        field={@footage_form[:start_date]}
                        id="footage_start_date"
                        type="datetime-local"
                        label="Start Date"
                        required
                      />
                    </div>

                    <div class="mr-4 w-full p-2 rounded">
                      <.input
                        field={@footage_form[:duration]}
                        id="footage_duration"
                        type="select"
                        label="Duration"
                        options={Enum.map(@durations, &{&1.label, &1.id})}
                        phx-change="update_end_date_visibility"
                        required
                      />
                    </div>

                    <div id="custom-end-date" class={if not @custom_duration, do: ["hidden"], else: [""]}>
                      <div class="mr-4 w-full p-2 rounded">
                        <.input
                          field={@footage_form[:end_date]}
                          id="footage_end_date"
                          type="datetime-local"
                          label="End Date"
                          required={@custom_duration}
                        />
                      </div>
                    </div>

                    <div class="mr-4 w-full p-2 rounded flex justify-center space-x-4">
                      <button id="close-popup-button" phx-click="hide_footage_popup" class="bg-red-500 text-white px-4 py-2 rounded flex items-center">
                        Cancel
                      </button>
                      <.button
                        class="bg-blue-500 text-white px-4 py-2 rounded flex items-center"
                        phx-submit="download_footage"
                        phx-disable-with="Downloading.."
                        >
                        Download
                      </.button>
                    </div>
                  </div>
                </.simple_form>
              </div>
            </div>
          <% end %>
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
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_footage_durations()
      |> assign_devices()
      |> assign_current_device()
      |> assign_streams()
      |> assign_form(nil)
      |> assign_footage_form(%{})
      |> assign_start_date(nil)
      |> live_view_enabled?()
      |> assign_runs()
      |> assign_timezone()
      |> maybe_push_stream_event(nil)

    {:ok, assign(socket, start_date: nil, show_footage_popup: false, custom_duration: false)}
  end

  def handle_event("switch_device", %{"device" => device_id}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    socket =
      socket
      |> assign_current_device(device)
      |> assign_streams()
      |> assign_form(nil)
      |> assign_footage_form(%{})
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

  def handle_event("update_end_date_visibility", %{"duration" => duration}, socket) do
    if duration == "custom", do: {:noreply, assign(socket, custom_duration: true)}, else:  {:noreply, assign(socket, custom_duration: false)}
  end

  def handle_event("show_footage_popup",_params, socket) do
    {:noreply, assign(socket, show_footage_popup: true)}
  end

  def handle_event("hide_footage_popup", _params, socket) do
    {:noreply, assign(socket, show_footage_popup: false)}
  end

  def handle_event("download_footage", %{"start_date" => start_date, "device" => device_id, "end_date" => end_date, "duration" => duration}, socket) do
    duration = convert_duration(duration)
    if end_date == "" and duration == "" do
      {:noreply, put_flash(socket, :error, "Either End date or Duration must be provided!"), show_footage_popup: false}
    else
      end_date = if end_date != "", do: format_to_datetime(end_date, socket.assigns.timezone), else: end_date
      start_date = format_to_datetime(start_date, socket.assigns.timezone)
      url = "/api/devices/#{device_id}/footage/?start_date=#{start_date}&end_date=#{end_date}&duration=#{duration}"

      {:noreply,
        socket
        |> assign(show_footage_popup: false)
        |> push_event("download-footage", %{url: url})}
    end
  end

  defp assign_footage_durations(socket) do
    durations = [
      %{label: "2 Minutes", id: "2_mins"},
      %{label: "5 Minutes", id: "5_mins"},
      %{label: "10 Minutes", id: "10_mins"},
      %{label: "30 Minutes", id: "30_mins"},
      %{label: "1 Hour", id: "1_hour"},
      %{label: "2 Hours", id: "2_hour"},
      %{label: "Custom", id: "custom"}
    ]
    assign(socket, durations: durations)
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

  defp assign_footage_form(socket, params) do
    assign(socket, footage_form: to_form(params))
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

  defp convert_timezone(datetime, timezone) do
    DateTime.new!(DateTime.to_date(datetime), DateTime.to_time(datetime), timezone)
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp format_to_datetime(datetime, timezone) do
    {:ok, new_format, _} = DateTime.from_iso8601("#{datetime}:00Z")
    new_format
    |> convert_timezone(timezone)
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)

  defp convert_duration(duration) do
    case duration do
      "2_mins" -> 2 * 60
      "5_mins" -> 5 * 60
      "10_mins" -> 10 * 60
      "30_mins" -> 30 * 60
      "1_hour" -> 60 * 60
      "2_hour" -> 120 * 60
      "custom" -> ""
    end
  end
end
