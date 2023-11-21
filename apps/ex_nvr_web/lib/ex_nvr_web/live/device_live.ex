defmodule ExNVRWeb.DeviceLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.{Devices, DeviceSupervisor}
  alias ExNVR.Model.Device

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = Devices.change_device_creation(%Device{})

    {:ok,
     assign(socket,
       device: %Device{},
       disks_data: get_disks_data(),
       device_form: to_form(changeset)
     )}
  end

  def mount(%{"id" => device_id}, _session, socket) do
    device = Devices.get!(device_id)

    {:ok,
     assign(socket,
       device: device,
       disks_data: get_disks_data(),
       device_form: to_form(Devices.change_device_update(device))
     )}
  end

  def handle_event("change_device_type", _params, socket) do
    {:noreply, push_event(socket, "toggle-device-config-inputs", %{})}
  end

  def handle_event("save_device", %{"device" => device_params}, socket) do
    device = socket.assigns.device

    if device.id,
      do: do_update_device(socket, device, device_params),
      else: do_save_device(socket, device_params)
  end

  defp do_save_device(socket, device_params) do
    case Devices.create(device_params) do
      {:ok, device} ->
        info = "Device created successfully"
        DeviceSupervisor.start(device)

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/devices")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply,
         assign(push_event(socket, "toggle-device-config-inputs", %{}),
           device_form: to_form(changeset)
         )}
    end
  end

  defp do_update_device(socket, device, device_params) do
    case Devices.update(device, device_params) do
      {:ok, updated_device} ->
        info = "Device updated successfully"

        if Device.recording?(device) and Device.config_updated(device, updated_device),
          do: DeviceSupervisor.restart(updated_device)

        socket
        |> put_flash(:info, info)
        |> assign(
          device: updated_device,
          device_form: to_form(Devices.change_device_update(updated_device))
        )
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply,
         assign(push_event(socket, "toggle-device-config-inputs", %{}),
           device_form: to_form(changeset)
         )}
    end
  end

  defp format_disk_entry({mountpoint, total_space, percent_free}) do
    "#{mountpoint} (capacity: #{humanize_capacity(total_space)}, free: #{percent_free}%)"
  end

  defp humanize_capacity(capacity) do
    cond do
      capacity / 1_000_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 3, 2)} TiB"
      capacity / 1_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 2, 2)} GiB"
      true -> "#{Float.round(capacity / 1024, 2)} MiB"
    end
  end

  defp get_disks_data() do
    if Mix.env() == :test do
      [{"/tmp", 1_000_000, 1}]
    else
      :disksup.get_disk_data()
      |> Enum.map(fn {mountpoint, total_space, percentage} ->
        {to_string(mountpoint), total_space, percentage}
      end)
      |> Enum.reject(fn {mountpoint, _, _} ->
        String.match?(mountpoint, ~r[/(dev|sys|run).*])
      end)
    end
  end
end
