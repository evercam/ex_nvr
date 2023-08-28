defmodule ExNVR.Pipeline.Source.RTSP.MediaTCPSocket do
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

  @impl true
  def init(connection_info, options) do
    case TCPSocket.init(connection_info, options) do
      {:ok, socket} ->
        {:ok, tcp_handler} =
          Task.start_link(fn ->
            handle_tcp_messages(socket, options[:media_receiver], false, nil, <<>>)
          end)

        {:ok, %{socket: socket, tcp_handler: tcp_handler}}

      other ->
        other
    end
  end

  @impl true
  def execute(request, %{tcp_handler: tcp_handler}, _options) do
    send(tcp_handler, {:request, request, self()})

    response =
      receive do
        {:response, response} when is_binary(response) ->
          {:ok, response}

        {:response, response} ->
          response
      end

    if elem(response, 0) == :ok and play?(request) do
      send(tcp_handler, :play)
    end

    response
  end

  @impl true
  defdelegate handle_info(msg, state), to: TCPSocket

  @impl true
  defdelegate close(state), to: TCPSocket

  defp play?(<<"PLAY", _::binary>>), do: true
  defp play?(_), do: false

  defp handle_tcp_messages(socket, media_received, false, requester, acc) do
    receive do
      :play ->
        handle_tcp_messages(socket, media_received, requester, acc)

      {:request, request, requester} ->
        response = TCPSocket.execute(request, socket, [])
        send(requester, {:response, response})
        handle_tcp_messages(socket, media_received, false, requester, acc)
    after
      2_000 -> handle_tcp_messages(socket, media_received, false, requester, acc)
    end
  end

  defp handle_tcp_messages(socket, media_receiver, requester, acc) do
    receive do
      :play ->
        handle_tcp_messages(socket, media_receiver, requester, acc)

      {:request, request, requester} ->
        :gen_tcp.send(socket, request)
        handle_tcp_messages(socket, media_receiver, requester, acc)
    after
      0 ->
        case read(socket, 4, acc) do
          {<<0x24::8, channel::8, size::16>>, acc} ->
            {packet, acc} = read(socket, size, acc)
            send(media_receiver, {:media_packet, channel, packet})
            handle_tcp_messages(socket, media_receiver, requester, acc)

          {"RTSP", acc} ->
            {response, acc} = parse_rtsp_response(socket, "RTSP" <> acc)

            if is_pid(requester) do
              send(requester, {:response, response})
            end

            handle_tcp_messages(socket, media_receiver, nil, acc)

          {_other, _acc} ->
            # ignore remaining packets in acc
            handle_tcp_messages(socket, media_receiver, nil, <<>>)
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
         {response, acc} <- do_parse_response(response) do
      {response, acc}
    else
      _other ->
        response = do_read_from_socket(socket, response)
        parse_rtsp_response(socket, response)
    end
  end

  defp do_parse_response(response) do
    with {:ok, %{body: body, headers: headers}} <- Response.parse(response),
         body_size <- content_length(headers),
         true <- byte_size(body) >= body_size do
      <<_ignore::binary-size(body_size), acc::binary>> = body
      response = :binary.part(response, 0, byte_size(response) - byte_size(acc))
      {response, acc}
    end
  end

  defp content_length(headers) do
    case List.keyfind(headers, "Content-Length", 0) do
      {"Content-Length", length_str} -> String.to_integer(length_str)
      nil -> 0
    end
  end
end
