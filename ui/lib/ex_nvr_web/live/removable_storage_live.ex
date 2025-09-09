defmodule ExNVRWeb.RemovableStorageLive do
  use ExNVRWeb, :live_view
  alias ExNvr.RemovableStorage.Mounter

  require Logger

  def mount(_, _, socket) do
    Phoenix.PubSub.subscribe(ExNVR.PubSub, "removable_storage_topic")

    {:ok,
     socket
     |> assign(removable_device: nil)}
  end

  def render(assigns) do
    ~H"""
    <div class="max-w-lg mx-auto text-white font-medium flex flex-col items-center space-y-6 mt-5">
      <h2 class="text-lg font-semibold">Copy To USB</h2>

      <%= if @removable_device do %>
        <div class="w-full space-y-4 mb-5">
          <h4 class="text-sm text-gray-300">Select storage address</h4>

          <.form
            for={}
            phx-change="select_partition"
            phx-submit="download"
            class="space-y-3"
          >
            <%= for device <- @removable_device.partitions do %>
              <label class="flex items-center p-3 rounded-lg border border-gray-600 bg-gray-700 cursor-pointer">
                <!-- Radio -->
                <input
                  type="radio"
                  name="partition"
                  value={device.name}
                  class="form-radio h-4 w-4 text-blue-500 border-gray-500 bg-gray-600"
                />
                <span class="ml-2 text-sm">
                  {List.first(device.mountpoints) || "/"}
                </span>

                <div class="flex-grow flex flex-col space-y-1 ml-3">
                  <span class="text-xs text-gray-400 self-end">{device.size}</span>
                </div>
              </label>
            <% end %>
          </.form>
        </div>
      <% else %>
        <p class="text-sm text-gray-400">No removable device detected</p>
      <% end %>
    </div>
    """
  end

  def handle_info({:usb, device}, socket) do
    {:noreply, assign(socket, :removable_device, device)}
  end

  def handle_event("select_partition", %{"partition" => partition} = _params, socket) do
    Mounter.mount(partition)
    {:noreply, socket}
  end
end
