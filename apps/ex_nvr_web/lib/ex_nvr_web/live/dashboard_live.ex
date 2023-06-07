defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices

  def render(assigns) do
    ~H"""
    <div class="bg-white sm:w-2/3 dark:bg-gray-800">
      <div :if={@devices == []} class="grid tracking-wide text-lg text-center dark:text-gray-200">
        You have no devices, you can create one
        <span><.link href={~p"/devices"} class="ml-2 dark:text-blue-600">here</.link></span>
      </div>
      <div :if={@devices != []}>
        <.simple_form id="device" class="my-4" for={@form}>
          <div class="flex items-center justify-between">
            <.input
              field={@form[:id]}
              type="select"
              label="Device"
              options={Enum.map(@devices, &{&1.name, &1.id})}
              value={@current_device.id}
              phx-change="switch_device"
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
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      case Devices.list() do
        [] ->
          assign(socket, devices: [], current_device: nil, form: to_form(%{}, as: "device"))

        devices ->
          current_device = List.first(devices)
          form = to_form(%{"id" => Map.get(current_device, :id)}, as: "device")

          socket =
            assign(socket,
              devices: devices,
              current_device: current_device,
              start_date: nil,
              form: form
            )

          if connected?(socket),
            do: stream_event(socket, nil),
            else: socket
      end

    {:ok, socket}
  end

  def handle_event("datetime", %{"value" => value}, socket) do
    date = socket.assigns.start_date
    datetime = if value == "", do: nil, else: value <> ":00Z"

    socket = if date != datetime, do: stream_event(socket, datetime), else: socket
    {:noreply, assign(socket, :start_date, datetime)}
  end

  def handle_event("switch_device", %{"device" => %{"id" => device_id}}, socket) do
    case Enum.find(socket.assigns.devices, &(&1.id == device_id)) do
      nil ->
        {:noreply, socket}

      device ->
        socket
        |> assign(current_device: device)
        |> stream_event(socket.assigns.start_date)
        |> then(&{:noreply, &1})
    end
  end

  defp stream_event(socket, datetime) do
    device = socket.assigns.current_device
    src = ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: datetime}}"
    push_event(socket, "stream", %{src: src})
  end
end
