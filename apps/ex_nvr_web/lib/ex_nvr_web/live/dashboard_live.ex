defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices
  alias ExNVR.Model.Device

  def render(assigns) do
    ~H"""
    <div class="bg-white sm:w-2/3 dark:bg-gray-800">
      <div :if={@devices == []} class="grid tracking-wide text-lg text-center dark:text-gray-200">
        You have no devices, you can create one
        <span><.link href={~p"/devices"} class="ml-2 dark:text-blue-600">here</.link></span>
      </div>
      <div :if={@devices != []}>
        <.simple_form id="device" class="my-4" for={@form}>
          <div class="flex items-center justify-between invisible sm:visible">
            <div class="flex items-center">
              <div class="mr-4">
                <.input
                  field={@form[:id]}
                  type="select"
                  label="Device"
                  options={Enum.map(@devices, &{&1.name, &1.id})}
                  value={@current_device.id}
                  phx-change="switch_device"
                />
              </div>

              <div class={[@start_date && "hidden"]}>
                <.input
                  field={@form[:stream]}
                  type="select"
                  label="Stream"
                  options={@supported_streams}
                  value={@current_stream}
                  phx-change="switch_stream"
                />
              </div>
            </div>

            <.input
              type="datetime-local"
              field={@form[:start_date]}
              label="Start date"
              phx-blur="datetime"
              max={Calendar.strftime(DateTime.utc_now(), "%Y-%m-%dT%H:%M")}
              value={@start_date && Calendar.strftime(@start_date, "%Y-%m-%dT%H:%M")}
            />
          </div>
        </.simple_form>

        <video id="live-video" class="my-4 w-full h-auto" poster="/spinner.gif" autoplay muted />
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      case Devices.list() do
        [] ->
          assign(socket, devices: [], current_device: nil)

        devices ->
          current_device = List.first(devices)
          form = to_form(%{"id" => Map.get(current_device, :id)}, as: "device")

          {current_stream, streams} = build_streams(current_device)

          socket =
            assign(socket,
              devices: devices,
              current_device: current_device,
              start_date: nil,
              form: form,
              supported_streams: streams,
              current_stream: current_stream
            )

          if connected?(socket),
            do: stream_event(socket, nil),
            else: socket
      end

    {:ok, socket}
  end

  def handle_event("datetime", %{"value" => value}, socket) do
    current_datetime = socket.assigns.start_date
    device = socket.assigns.current_device

    new_datetime = parse_datetime(value, device.timezone)

    socket =
      if current_datetime != new_datetime, do: stream_event(socket, new_datetime), else: socket

    {:noreply, assign(socket, :start_date, new_datetime)}
  end

  def handle_event("switch_device", %{"device" => %{"id" => device_id}}, socket) do
    case Enum.find(socket.assigns.devices, &(&1.id == device_id)) do
      nil ->
        {:noreply, socket}

      device ->
        {current_stream, streams} = build_streams(device)

        socket
        |> assign(
          current_device: device,
          supported_streams: streams,
          current_stream: current_stream
        )
        |> stream_event(socket.assigns.start_date)
        |> then(&{:noreply, &1})
    end
  end

  def handle_event("switch_stream", %{"device" => %{"stream" => selected_stream}}, socket) do
    current_stream = socket.assigns.current_stream

    if current_stream != selected_stream do
      socket
      |> assign(current_stream: selected_stream)
      |> stream_event(socket.assigns.start_date)
      |> then(&{:noreply, &1})
    else
      {:noreply, socket}
    end
  end

  defp stream_event(socket, datetime) do
    device = socket.assigns.current_device
    current_stream = if socket.assigns.current_stream == "main_stream", do: 0, else: 1

    src =
      ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: format_date(datetime), stream: current_stream}}"

    push_event(socket, "stream", %{src: src})
  end

  defp build_streams(%Device{} = device) do
    if Device.has_sub_stream(device) do
      {"sub_stream", [{"Main Stream", "main_stream"}, {"Sub Stream", "sub_stream"}]}
    else
      {"main_stream", [{"Main Stream", "main_stream"}]}
    end
  end

  defp parse_datetime(datetime, timezone) do
    case NaiveDateTime.from_iso8601(datetime <> ":00") do
      {:ok, date} -> DateTime.from_naive!(date, timezone)
      _ -> nil
    end
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)
end
