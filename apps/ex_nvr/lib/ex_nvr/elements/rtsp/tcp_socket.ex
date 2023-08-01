defmodule ExNVR.Elements.RTSP.TCPSocket do
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

  alias Membrane.RTSP.{Response, Transport.TCPSocket}

  @media_wait_timeout 10_000
  @dummy_rtsp_response "RTSP/1.0 200 OK\nCSeq: 0\r\n\r\n"

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
    if (pid = Process.whereis(:media_handler)) && Process.alive?(pid) do
      # If a message arrive after the PLAY request, it's
      # a keep alive message. No need to check for an error since
      # the session will fail eventually if there's no media packets
      send(pid, {:request, request})
      {:ok, @dummy_rtsp_response}
    else
      with {:ok, data} <- TCPSocket.execute(request, socket, options) do
        if play?(request) do
          spawn_link(fn -> handle_media_packets(socket, media_receiver) end)
        end

        {:ok, data}
      end
    end
  end

  @impl true
  defdelegate handle_info(msg, state), to: TCPSocket

  @impl true
  defdelegate close(state), to: TCPSocket

  defp play?(<<"PLAY", _::binary>>), do: true
  defp play?(_), do: false

  defp handle_media_packets(socket, media_received) do
    Process.register(self(), :media_handler)
    do_handle_media_packets(socket, media_received)
  end

  defp do_handle_media_packets(socket, media_receiver, acc \\ <<>>) do
    receive do
      {:request, request} ->
        :gen_tcp.send(socket, request)
        do_handle_media_packets(socket, media_receiver, acc)
    after
      0 ->
        case read(socket, 4, acc) do
          {<<0x24::8, _channel::8, size::16>>, acc} ->
            {packet, acc} = read(socket, size, acc)
            send(media_receiver, {:media_packet, packet})
            do_handle_media_packets(socket, media_receiver, acc)

          {"RTSP", acc} ->
            acc = parse_rtsp_response(socket, "RTSP" <> acc)
            do_handle_media_packets(socket, media_receiver, acc)

          {_other, _acc} ->
            # ignore remaining packets in acc
            do_handle_media_packets(socket, media_receiver, <<>>)
        end
    end
  end

  defp read(socket, size, acc) do
    case acc do
      <<data::binary-size(size), rest::binary>> ->
        {data, rest}

      acc ->
        acc = do_read_from_socket(socket, acc)
        read(socket, size, acc)
    end
  end

  defp do_read_from_socket(socket, acc) do
    case :gen_tcp.recv(socket, 0, @media_wait_timeout) do
      {:ok, data} ->
        acc <> data

      {:error, :ealready} ->
        Process.sleep(10)
        do_read_from_socket(socket, acc)

      {:error, reason} ->
        raise "connection lost due to: #{inspect(reason)}"
    end
  end

  defp parse_rtsp_response(socket, response) do
    with {_pos, _length} <- :binary.match(response, ["\r\n\r\n", "\n\n", "\r\r"]),
         acc when is_binary(acc) <- do_parse_response(response) do
      acc
    else
      _other ->
        response = do_read_from_socket(socket, response)
        parse_rtsp_response(socket, response)
    end
  end

  defp do_parse_response(response) do
    with {:ok, %{body: body, headers: headers}} <- Response.parse(response),
         {"Content-Length", length_str} <- List.keyfind(headers, "Content-Length", 0),
         content_length <- String.to_integer(length_str),
         true <- byte_size(body) >= content_length do
      <<_ignore::binary-size(content_length), acc::binary>> = body
      acc
    end
  end
end
