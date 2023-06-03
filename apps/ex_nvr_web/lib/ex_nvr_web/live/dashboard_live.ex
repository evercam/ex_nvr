defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices

  def render(assigns) do
    ~H"""
    <div class="bg-white dark:bg-gray-800">
      <.simple_form id="device" class="my-4" for={@form}>
        <div class="flex items-center justify-between">
          <.input
            field={@form[:id]}
            type="select"
            label="Device"
            options={Enum.map(@devices, &{&1.name, &1.id})}
          />

          <.input
            type="datetime-local"
            field={@form[:start_date]}
            label="Start date"
            phx-blur="datetime"
            max={Calendar.strftime(DateTime.utc_now(), "%Y-%m-%dT%H:%M")}
          />
        </div>
      </.simple_form>

      <video id="live-video" class="my-4 w-full h-auto" poster="/spinner.gif" autoplay muted />
    </div>
    """
  end

  def mount(_params, _session, socket) do
    devices = Devices.list()
    current_device = List.first(devices)
    form = to_form(%{"id" => Map.get(current_device, :id)}, as: "device")

    socket =
      assign(socket, devices: devices, current_device: current_device, start_date: nil, form: form)

    socket =
      if connected?(socket),
        do: stream_event(socket, nil),
        else: socket

    {:ok, socket}
  end

  def handle_event("datetime", %{"value" => value}, socket) do
    %{start_date: date, current_device: device} = socket.assigns
    datetime = if value == "", do: nil, else: value <> ":00Z"

    socket = if date != datetime, do: stream_event(socket, datetime), else: socket
    {:noreply, assign(socket, :start_date, datetime)}
  end

  defp stream_event(socket, datetime) do
    device = socket.assigns.current_device
    src = ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: datetime}}"
    push_event(socket, "stream", %{src: src})
  end
end
