defmodule ExNVR.RTSP.TCPSocket do
  @moduledoc """
  This module is a wrapper around Membrane.RTSP.Transport.TCPSocket and augments
  it with the possibility to receive media data via the same connection that's used for
  the RTSP session.

  Supported options:
    * connection_timeout - time after request will be deemed missing and error shall be
     returned.
    * media_receiver - The pid of a process where to send media data
  """

  use Membrane.RTSP.Transport

  require Membrane.Logger

  alias Membrane.RTSP.Transport.TCPSocket

  @media_wait_timeout 10_000

  @impl true
  def init(connection_info, options) do
    case TCPSocket.init(connection_info, options) do
      {:ok, socket} ->
        {:ok, %{socket: socket, media_receiver: options[:media_receiver]}}

      other ->
        other
    end
  end

  @impl true
  def execute(request, %{socket: socket, media_receiver: media_receiver}, options) do
    with {:ok, data} <- TCPSocket.execute(request, socket, options) do
      if play?(request) do
        spawn_link(fn -> handle_media_packets(socket, media_receiver) end)
      end

      {:ok, data}
    end
  end

  @impl true
  defdelegate handle_info(msg, state), to: TCPSocket

  @impl true
  defdelegate close(state), to: TCPSocket

  defp play?(<<"PLAY", _::binary>>), do: true
  defp play?(_), do: false

  defp handle_media_packets(socket, media_receiver) do
    with {:ok, <<0x24::8, _channel::8, size::16>>} <-
           :gen_tcp.recv(socket, 4, @media_wait_timeout),
         {:ok, packet} when byte_size(packet) == size <-
           :gen_tcp.recv(socket, size, @media_wait_timeout) do
      send(media_receiver, {:media_packet, packet})
      handle_media_packets(socket, media_receiver)
    else
      {:error, reason} ->
        send(media_receiver, {:rtsp_connection_lost, reason})

      _ ->
        Membrane.Logger.debug("ignore packet, not an RTP packet")
        handle_media_packets(socket, media_receiver)
    end
  end
end
