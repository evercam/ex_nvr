defmodule ExNVRWeb.DeviceLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExMP4.Reader
  alias ExNVR.{Devices, RemoteStorages}
  alias ExNVR.Model.Device

  def mount(%{"id" => "new"}, _session, socket) do
    device_params = get_device_params(socket.assigns.flash)
    device = init_device(device_params)
    changeset = Devices.change_device_creation(%Device{}, device_params)

    {:ok,
     socket
     |> assign(
       device: device,
       disks_data: get_disks_data(),
       device_form: to_form(changeset),
       device_type: "ip",
       override_on_full_disk: false,
       remote_storages: list_remote_storages()
     )
     |> allow_upload(:file_to_upload,
       accept: ~w(video/mp4),
       max_file_size: 1_000_000_000
     )}
  end

  def mount(%{"id" => device_id}, _session, socket) do
    device = Devices.get!(device_id)
    device_params = get_device_params(socket.assigns.flash) |> Map.delete(:name)
IO.inspect(device)
    {:ok,
     assign(socket,
       device: device,
       disks_data: get_disks_data(),
       device_form: to_form(Devices.change_device_update(device, device_params)),
       device_type: Atom.to_string(device.type),
       remote_storages: list_remote_storages()
     )}
  end

  def handle_event("validate", %{"device" => device_params}, socket) do
    device = socket.assigns.device

    {device_type, changeset} = get_validation_assigns(device, device_params)

    changeset
    |> Map.put(:action, :validate)
    |> then(
      &assign(
        socket,
        device_form: to_form(&1),
        device_type: device_type,
        override_on_full_disk: device_params["settings"]["override_on_full_disk"] == "true"
      )
    )
    |> then(&{:noreply, &1})
  end

  def handle_event("update_storage_schedule", new_schedule, socket) do
    {:noreply, assign(socket, storage_schedule: new_schedule)}
  end

  def handle_event("update_snapshot_schedule", new_schedule, socket) do
    {:noreply, assign(socket, snapshot_schedule: new_schedule)}
  end

  def handle_event("save_device", %{"device" => device_params}, socket) do
    device = socket.assigns.device
    device_type = socket.assigns.device_type

    device_params = device_params
      |> put_snapshot_schedule(socket.assigns.snapshot_schedule, device_type)
      |> put_storage_schedule(socket.assigns.storage_schedule)

    IO.inspect(device_params)
    if device.id,
      do: do_update_device(socket, device, device_params),
      else: do_save_device(socket, device_params)
  end

  def error_to_string(:too_large), do: "Too large"
  def error_to_string(:not_accepted), do: "You have selected an unacceptable file type"

  defp get_device_params(%{"device_params" => device_params}), do: device_params
  defp get_device_params(_flash), do: %{}

  defp init_device(%{model: model, url: url, mac: mac}) do
    %Device{model: model, url: url, mac: mac}
  end

  defp init_device(_device_params) do
    %Device{}
  end

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

  defp put_snapshot_schedule(params, _schedule, "file"), do: params

  defp put_snapshot_schedule(
         %{"snapshot_config" => %{"enabled" => false}} = params,
        _schedule,
         "ip"
       ),
       do: params

  defp put_snapshot_schedule(
         %{"snapshot_config" => snapshot} = params,
          nil,
         "ip"
       ) do
    Map.put(params, "snapshot_config", Map.put(snapshot, "schedule", default_schedule()))
  end

  defp put_snapshot_schedule(
         %{"snapshot_config" => snapshot} = params,
          schedule,
         "ip"
       ) do
    Map.put(params, "snapshot_config", Map.put(snapshot, "schedule", schedule))
  end


  defp put_storage_schedule(%{"storage_config" => storage} = params, nil) do
    Map.put(params, "storage_config", Map.put(storage, "schedule", default_schedule()))
  end

  defp put_storage_schedule(%{"storage_config" => storage} = params, schedule) do
    Map.put(params, "storage_config", Map.put(storage, "schedule", schedule))
  end


  defp default_schedule do
    for day <- 1..7, into: %{} do
      {Integer.to_string(day), ["00:00-23:59"]}
    end
  end

  defp do_save_device(socket, device_params) do
    device_params =
      socket.assigns.device
      |> Map.take([:mac, :model, :url])
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.merge(device_params)

    socket
    |> handle_uploaded_file(device_params)
    |> Devices.create()
    |> case do
      {:ok, _device} ->
        info = "Device created successfully"

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
    with [{path, filename}] <- consume_uploaded_file(socket),
         {:ok, reader} <- Reader.new(path) do
      Map.put(device_params, "stream_config", %{
        "temporary_path" => path,
        "filename" => filename,
        "duration" => Reader.duration(reader, :microsecond)
      })
    end
  end

  defp consume_uploaded_file(socket) do
    consume_uploaded_entries(socket, :file_to_upload, fn %{path: path}, entry ->
      {:postpone, {path, entry.client_name}}
    end)
  end

  defp do_update_device(socket, device, device_params) do
    case Devices.update(device, device_params) do
      {:ok, _updated_device} ->
        info = "Device updated successfully"

        socket
        |> put_flash(:info, info)
        |> redirect(to: ~p"/devices")
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, device_form: to_form(changeset))}
    end
  end

  defp list_remote_storages do
    RemoteStorages.list() |> Enum.map(& &1.name)
  end

  defp humanize_capacity({capacity, _percentag}) do
    cond do
      capacity / 1_000_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 3, 2)} TiB"
      capacity / 1_000_000 >= 1 -> "#{Float.round(capacity / 1024 ** 2, 2)} GiB"
      true -> "#{Float.round(capacity / 1024, 2)} MiB"
    end
  end

  defp get_disks_data do
    if Application.get_env(:ex_nvr, :env) == :test do
      [{"/tmp", {1_000_000, 1}}]
    else
      :disksup.get_disk_data()
      |> Enum.map(fn {mountpoint, total_space, percentage} ->
        {to_string(mountpoint), {total_space, percentage}}
      end)
      |> Enum.reject(fn {mountpoint, _value} ->
        String.match?(mountpoint, ~r[/(dev|sys|run|tmp|boot)])
      end)
    end
  end
end
