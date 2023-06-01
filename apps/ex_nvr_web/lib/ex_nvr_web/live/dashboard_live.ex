defmodule ExNVRWeb.DashboardLive do
  use ExNVRWeb, :live_view

  alias ExNVR.Devices

  def render(assigns) do
    ~H"""
    <div class="flex flex-col bg-white dark:bg-gray-800">
      <div class="my-4 flex">
        <.simple_form for={@form}>
          <.input
            field={@form[:id]}
            type="select"
            label="Device"
            options={Enum.map(@devices, &{&1.name, &1.id})}
          />
        </.simple_form>
      </div>

      <video id="live-video" class="my-4 w-full h-auto" poster="/spinner.gif" autoplay muted />
    </div>

    <script src="https://cdn.jsdelivr.net/npm/hls.js@1" />
    <script>
      var video = document.getElementById('live-video');
      var videoSrc = '/api/devices/<%= @current_device.id %>/hls/index.m3u8';
      if (Hls.isSupported()) {
        var hls = new Hls();
        hls.loadSource(videoSrc);
        hls.attachMedia(video);
      }
    </script>
    """
  end

  def mount(_params, _session, socket) do
    devices = Devices.list()
    current_device = List.first(devices)
    form = to_form(%{"id" => Map.get(current_device, :id)}, as: "device")

    {:ok, assign(socket, devices: devices, current_device: current_device, form: form)}
  end
end
