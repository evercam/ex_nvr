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

          <div class="mt-5">
            <.input
              type="datetime-local"
              name="device_start_date"
              id="device_start_time"
              label="Start date"
              phx-blur="datetime"
              max={Calendar.strftime(DateTime.utc_now(), "%Y-%m-%dT%H:%M")}
              value={@start_date && Calendar.strftime(@start_date, "%Y-%m-%dT%H:%M")}
            />
          </div>
        </div>

        <div :if={not @live_view_enabled?} class="mt-10 text-lg text-center dark:text-gray-200">
          Device is not recording, live view is not available
        </div>

        <video
          :if={@live_view_enabled?}
          id="live-video"
          class="my-4 w-full h-auto"
          poster="/spinner.gif"
          autoplay
          muted
        />
      </div>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_devices()
      |> assign_current_device()
      |> assign_streams()
      |> assign_form(nil)
      |> assign_start_date(nil)
      |> live_view_enabled?()
      |> maybe_push_stream_event(nil)

    {:ok, assign(socket, start_date: nil)}
  end

  def handle_event("switch_device", %{"device" => device_id}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    socket =
      socket
      |> assign_current_device(device)
      |> assign_streams()
      |> assign_form(nil)
      |> live_view_enabled?()
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
    device = socket.assigns.current_device
    new_datetime = parse_datetime(value, device.timezone)

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

  defp assign_form(%{assigns: %{current_device: nil}} = socket, _params), do: socket

  defp assign_form(socket, nil) do
    device = socket.assigns.current_device
    stream = if Device.has_sub_stream(device), do: "sub_stream", else: "main_stream"
    assign(socket, form: to_form(%{"device" => device.id, "stream" => stream}))
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

        src =
          ~p"/api/devices/#{device.id}/hls/index.m3u8?#{%{pos: format_date(datetime), stream: current_stream}}"

        push_event(socket, "stream", %{src: src})
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

  defp parse_datetime(datetime, timezone) do
    case NaiveDateTime.from_iso8601(datetime <> ":00") do
      {:ok, date} -> DateTime.from_naive!(date, timezone)
      _ -> nil
    end
  end

  defp format_date(nil), do: nil
  defp format_date(datetime), do: DateTime.to_iso8601(datetime)
end
