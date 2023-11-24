defmodule ExNVRWeb.DeviceLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.{Devices, DeviceSupervisor, Utils}
  alias ExNVR.Model.Device
  alias ExNVR.MP4.Reader

  @env Mix.env()

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = Devices.change_device_creation(%Device{})

    {:ok,
     socket
     |> assign(
       device: %Device{},
       disks_data: get_disks_data(),
       device_form: to_form(changeset),
       device_type: "ip"
     )
     |> allow_upload(:file_to_upload,
       accept: ~w(video/mp4),
       max_file_size: 1_000_000_000
     )}
  end

  def mount(%{"id" => device_id}, _session, socket) do
    device = Devices.get!(device_id)

    {:ok,
     assign(socket,
       device: device,
       disks_data: get_disks_data(),
       device_form: to_form(Devices.change_device_update(device)),
       device_type: Atom.to_string(device.type)
     )}
  end

  def handle_event("validate", %{"device" => device_params}, socket) do
    device = socket.assigns.device

    {device_type, changeset} = get_validation_assigns(device, device_params)

    changeset
    |> Map.put(:action, :validate)
    |> then(&assign(socket, device_form: to_form(&1), device_type: device_type))
    |> then(&{:noreply, &1})
  end

  def handle_event("save_device", %{"device" => device_params}, socket) do
    device = socket.assigns.device

    if device.id,
      do: do_update_device(socket, device, device_params),
      else: do_save_device(socket, device_params)
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp get_validation_assigns(%{id: id} = device, device_params) when not is_nil(id) do
    device_type = Atom.to_string(device.type)
    changeset = Devices.change_device_update(device, device_params)
    {device_type, changeset}
  end

  defp get_validation_assigns(_device, device_params) do
    device_type = device_params["type"]
    changeset = Devices.change_device_creation(%Device{}, device_params)
    {device_type, changeset}
  end

  defp do_save_device(socket, device_params) do
    socket
    |> handle_uploaded_file(device_params)
    |> Devices.create()
    |> case do
      {:ok, device} ->
        info = "Device created successfully"
        DeviceSupervisor.start(device)

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/devices")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, device_form: to_form(changeset))}
    end
  end

  defp handle_uploaded_file(_socket, %{"type" => "ip"} = device_params) do
    device_params
  end

  defp handle_uploaded_file(socket, device_params) do
    with [path] <- consume_uploaded_file(socket),
         {:ok, mp4_reader} <- Reader.new(path) do
      device_params
      |> Kernel.put_in(["stream_config", "location"], path)
      |> Kernel.put_in(["stream_config", "duration"], mp4_reader.duration)
    end
  end

  defp consume_uploaded_file(socket) do
    consume_uploaded_entries(socket, :file_to_upload, fn %{path: path}, entry ->
      dest = Path.join(Utils.device_file_dir(), Path.basename(entry.client_name))
      File.cp!(path, dest)
      {:ok, dest}
    end)
  end

  defp do_update_device(socket, device, device_params) do
    case Devices.update(device, device_params) do
      {:ok, updated_device} ->
        info = "Device updated successfully"

        if Device.recording?(device) and Device.config_updated(device, updated_device),
          do: DeviceSupervisor.restart(updated_device)

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/devices")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, device_form: to_form(changeset))}
    end
  end

  defp humanize_capacity(capacity) do
    cond do
      capacity / 1_000_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 3, 2)} TiB"
      capacity / 1_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 2, 2)} GiB"
      true -> "#{Float.round(capacity / 1024, 2)} MiB"
    end
  end

  defp get_disks_data() do
    if @env == :test do
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
