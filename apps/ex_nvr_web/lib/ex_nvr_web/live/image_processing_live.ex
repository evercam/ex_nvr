defmodule ExNVRWeb.ImageProcessingLive do
  use ExNVRWeb, :live_view

  require Logger
  alias ExNVR.Devices
  alias ExNVR.Pipelines.Main
  alias ExNVR.ImageProcessor

  def render(assigns) do
    ~H"""
      <div class="bg-white w-full dark:bg-gray-800">
        <%= if @devices == [] do %>
          <div class="grid tracking-wide text-lg text-center dark:text-gray-200">
            You have no devices, you can create one
            <span><.link href={~p"/devices"} class="ml-2 dark:text-blue-600">here</.link></span>
          </div>
        <% else %>
          <div>
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
                </div>
              </.simple_form>
            </div>

            <div class="relative mt-4">
              <%= if @live_view_enabled? do %>
                <div class="relative">
                  <%= if @current_snapshot.loading do %>
                    <svg
                      aria-hidden="true"
                      class="w-24 h-24 mt-20 mx-auto text-gray-200 animate-spin dark:text-gray-600 fill-blue-600"
                      viewBox="0 0 100 101"
                      fill="none"
                      xmlns="http://www.w3.org/2000/svg"
                    >
                      <path d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z" fill="currentColor"/>
                      <path d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z" fill="currentFill"/>
                    </svg>
                  <% else %>
                    <%= if @current_snapshot.ok? && @current_snapshot.result do %>
                      <div class="flex flex-row space-x-5">
                        <div class="w-1/2 flex flex-col">
                          <span class="dark:text-white"> Before </span>
                          <img
                            id="snapshot-before"
                            class="h-full dark:bg-gray-500 rounded-tr rounded-tl"
                            src={"data:image/png;base64,#{@current_snapshot.result.before}"}
                          />
                        </div>
                        <div class="w-1/2 h-full flex flex-col">
                          <span class="dark:text-white"> After </span>
                          <img
                            id="snapshot-after"
                            class="h-full dark:bg-gray-500 rounded-tr rounded-tl"
                            src={"data:image/png;base64,#{@current_snapshot.result.after}"}
                          />
                        </div>
                      </div>
                    <% end %>
                  <% end %>
                </div>
              <% else %>
                <div
                  class="relative text-lg rounded-tr rounded-tl text-center dark:text-gray-200 mt-4 w-full dark:bg-gray-500 h-96 flex justify-center items-center d-flex"
                >
                  Device is not recording, live view is not available
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    """
  end

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign_devices()
      |> assign_current_device()
      |> assign_form(nil)
      |> live_view_enabled?()
      |> assign_current_snapshot()

    {:ok, socket}
  end

  def handle_event("switch_device", %{"device" => device_id}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.id == device_id))

    socket =
      socket
      |> assign_current_device(device)
      |> assign_form(nil)
      |> live_view_enabled?()
      |> assign_current_snapshot()

    {:noreply, socket}
  end

  defp assign_devices(socket) do
    assign(socket, devices: Devices.list())
  end

  defp assign_current_device(socket, device \\ nil) do
    devices = socket.assigns.devices
    assign(socket, current_device: device || List.first(devices))
  end

  defp assign_form(%{assigns: %{current_device: nil}} = socket, _params), do: socket
  defp assign_form(socket, nil) do
    device = socket.assigns.current_device
    assign(socket, form: to_form(%{"device" => device.id}))
  end
  defp assign_form(socket, params) do
    assign(socket, form: to_form(params))
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

  defp assign_current_snapshot(%{assigns: %{current_device: nil}} = socket), do: assign_async(socket, :current_snapshot, {:ok, %{current_snapshot: ""}})
  defp assign_current_snapshot(%{assigns: %{live_view_enabled: false}} = socket), do: assign_async(socket, :current_snapshot, {:ok, %{current_snapshot: ""}})
  defp assign_current_snapshot(%{assigns: %{current_device: current_device}} = socket) do
    assign_async(
      socket,
      :current_snapshot,
      fn ->
        with {:ok, snapshot_byte} <- Main.live_snapshot(current_device, :png),
            processed_image <- ImageProcessor.undistort_snapshot(snapshot_byte),
            snapshot <- Base.encode64(snapshot_byte) do
          {:ok, %{current_snapshot: %{before: snapshot, after: processed_image}}}
        else
          _ -> {:failed, "couldn't get the message"}
        end
      end)
  end
end
