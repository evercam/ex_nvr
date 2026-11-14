defmodule ExNVRWeb.DeviceStreamChannel do
  @moduledoc false

  use ExNVRWeb, :channel

  require Logger

  alias ExNVR.Pipelines.Main, as: MainPipeline

  @impl true
  def join("stream:" <> device_id, params, socket) do
    device = ExNVR.Devices.get!(device_id)
    stream = parse_stream(params["stream"])

    case MainPipeline.add_binary_peer(device, stream) do
      {:ok, codec} ->
        {:ok, %{codec: codec}, assign(socket, device: device, stream: stream)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def handle_info({:hevc_frame, data}, socket) do
    payload = Enum.map_join(data, &<<0, 0, 0, 1, &1::binary>>)
    push(socket, "frame", {:binary, payload})
    {:noreply, socket}
  end

  @impl true
  def handle_info(message, socket) do
    Logger.warning("DeviceStreamChannel: unexpected message: #{inspect(message)}")
    {:noreply, socket}
  end

  defp parse_stream("low"), do: :low
  defp parse_stream(_), do: :high
end
