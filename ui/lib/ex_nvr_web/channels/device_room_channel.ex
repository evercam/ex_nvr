defmodule ExNVRWeb.DeviceRoomChannel do
  @moduledoc false

  use ExNVRWeb, :channel

  require Logger

  alias ExNVR.Pipelines.Main, as: MainPipeline

  @impl true
  def join("device:" <> device_id, params, socket) do
    device = ExNVR.Devices.get!(device_id)
    stream = parse_stream(params["stream"])

    case MainPipeline.add_webrtc_peer(device, stream) do
      :ok ->
        {:ok, assign(socket, device: device, stream: stream)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_in("answer", answer, socket) do
    MainPipeline.forward_peer_message(
      socket.assigns.device,
      socket.assigns.stream,
      {:answer, Jason.decode!(answer)}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_in("ice_candidate", candidate, socket) do
    MainPipeline.forward_peer_message(
      socket.assigns.device,
      socket.assigns.stream,
      {:ice_candidate, Jason.decode!(candidate)}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:offer, offer}, socket) do
    push(socket, "offer", %{data: Jason.encode!(offer)})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:ice_candidate, ice_candidate}, socket) do
    push(socket, "ice_candidate", %{data: Jason.encode!(ice_candidate)})
    {:noreply, socket}
  end

  @impl true
  def handle_info(message, socket) do
    Logger.warning("""
    Received unexpected message
    #{inspect(message)}
    """)

    {:noreply, socket}
  end

  defp parse_stream("low"), do: :low
  defp parse_stream(_other), do: :high
end
