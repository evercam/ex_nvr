defmodule ExNVRWeb.DeviceLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  import ExNVR.Authorization
  import ExNVRWeb.Live.Helpers

  alias ExNVR.{Devices, DeviceSupervisor}
  alias ExNVR.Model.Device
  alias ExNVR.MP4.Reader

  @env Mix.env()

  def mount(%{"id" => "new"}, _session, socket) do
    changeset = Devices.change_device_creation(%Device{})
    role = socket.assigns.current_user.role

    if is_authorized?(role, :device, :create),
      do:
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
         )},
      else: unauthorized(socket, ~p"/devices", :ok)
  end

  def mount(%{"id" => device_id}, _session, socket) do
    device = Devices.get!(device_id)
    role = socket.assigns.current_user.role

    if is_authorized?(role, :device, :update),
      do:
        {:ok,
         assign(socket,
           device: device,
           disks_data: get_disks_data(),
           device_form: to_form(Devices.change_device_update(device)),
           device_type: Atom.to_string(device.type)
         )},
      else: unauthorized(socket, ~p"/devices", :ok)
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
    role = socket.assigns.current_user.role

    with true <- is_authorized?(role, :device, :create),
         {:ok, device} <- socket |> handle_uploaded_file(device_params) |> Devices.create() do
      info = "Device created successfully"
      DeviceSupervisor.start(device)

      socket
      |> put_flash(:info, info)
      |> redirect(to: ~p"/devices")
      |> then(&{:noreply, &1})
    else
      false ->
        unauthorized(socket, ~p"/devices", :noreply)

      {:error, changeset} ->
        {:noreply, assign(socket, device_form: to_form(changeset))}
    end
  end

  defp handle_uploaded_file(_socket, %{"type" => "ip"} = device_params) do
    device_params
  end

  defp handle_uploaded_file(socket, device_params) do
    with [{path, filename}] <- consume_uploaded_file(socket),
         {:ok, reader} <- Reader.new(path) do
      Map.put(device_params, "stream_config", %{
        "temporary_path" => path,
        "filename" => filename,
        "duration" => Reader.duration(reader)
      })
    end
  end

  defp consume_uploaded_file(socket) do
    consume_uploaded_entries(socket, :file_to_upload, fn %{path: path}, entry ->
      {:postpone, {path, entry.client_name}}
    end)
  end

  defp do_update_device(socket, device, device_params) do
    role = socket.assigns.current_user.role

    with true <- is_authorized?(role, :device, :update),
         {:ok, updated_device} <- Devices.update(device, device_params) do
      info = "Device updated successfully"

      if Device.recording?(device) and Device.config_updated(device, updated_device),
        do: DeviceSupervisor.restart(updated_device)

      socket
      |> put_flash(:info, info)
      |> redirect(to: ~p"/devices")
      |> then(&{:noreply, &1})
    else
      false ->
        unauthorized(socket, ~p"/devices", :noreply)

      {:error, changeset} ->
        {:noreply, assign(socket, device_form: to_form(changeset))}
    end
  end

  defp humanize_capacity({capacity, _percentag}) do
    cond do
      capacity / 1_000_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 3, 2)} TiB"
      capacity / 1_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 2, 2)} GiB"
      true -> "#{Float.round(capacity / 1024, 2)} MiB"
    end
  end

  defp get_disks_data() do
    if @env == :test do
      [{"/tmp", {1_000_000, 1}}]
    else
      :disksup.get_disk_data()
      |> Enum.map(fn {mountpoint, total_space, percentage} ->
        {to_string(mountpoint), {total_space, percentage}}
      end)
      |> Enum.reject(fn {mountpoint, _value} ->
        String.match?(mountpoint, ~r[/(dev|sys|run).*])
      end)
    end
  end
end
