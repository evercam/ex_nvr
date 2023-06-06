defmodule ExNVRWeb.DeviceLive do
  @moduledoc false

  use ExNVRWeb, :live_view

  alias ExNVR.{Devices, Pipelines}
  alias ExNVR.Model.Device

  @device_modal_id "device-modal-container"

  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       devices: Devices.list(),
       form: new_device_form(),
       device_modal_id: @device_modal_id
     )}
  end

  def handle_event("save_device", %{"device" => device_params}, socket) do
    devices = socket.assigns.devices

    case Devices.create(device_params) do
      {:ok, device} ->
        info = "Device created successfully"

        if Application.get_env(:ex_nvr, :run_pipelines, true),
          do: Pipelines.Supervisor.start_pipeline(device)

        socket
        |> put_flash(:info, info)
        |> assign(devices: devices ++ [device], form: new_device_form())
        |> push_event("js-exec", %{
          to: "##{@device_modal_id}",
          attr: "data-hide"
        })
        |> then(&{:noreply, &1})

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp new_device_form(), do: to_form(Device.create_changeset(%{}))
end
