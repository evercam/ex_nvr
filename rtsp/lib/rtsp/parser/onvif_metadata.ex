defmodule ExNVR.RTSP.Parser.OnvifMetadata do
  @moduledoc false

  @behaviour ExNVR.RTSP.Parser

  require Logger

  alias ExNVR.RTSP.OnvifMetadata
  alias Membrane.Buffer
  alias Onvif.Schemas.MetadataStream

  @impl true
  def init(_opts), do: %{stream_format: %OnvifMetadata{}, acc: <<>>}

  @impl true
  def handle_discontinuity(state), do: state

  @impl true
  def handle_packet(packet, %{stream_format: nil} = state) do
    {:ok, do_handle_packet(packet, state)}
  end

  @impl true
  def handle_packet(packet, %{stream_format: stream_format} = state) do
    {buffers, state} = do_handle_packet(packet, state)
    {:ok, {[stream_format | buffers], %{state | stream_format: nil}}}
  end

  defp do_handle_packet(packet, state) do
    payload = state.acc <> packet.payload

    case packet.marker do
      true ->
        {do_parse_metadata(payload, packet.timestamp), %{state | acc: <<>>}}

      false ->
        {[], %{state | acc: payload}}
    end
  end

  defp do_parse_metadata(payload, timestamp) do
    payload
    |> MetadataStream.parse()
    |> MetadataStream.to_struct()
    |> case do
      {:ok, metadata} ->
        [%Buffer{payload: payload, pts: timestamp}]

      {:error, _changeset} ->
        Logger.error("""
        Could not parse stream metadata
        Payload: #{inspect(payload, limit: :infinity)}
        """)

        []
    end
  end
end
