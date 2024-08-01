defmodule ExNVR.RTSP.Source.PacketSplitter do
  @moduledoc """
  Split the incoming network packets into RTSP, RTP and RTCP packets.
  """

  require Logger

  alias Membrane.RTSP

  @max_buffer_size 5 * 1024 * 1024

  @doc """
  Split the binary into RTSP, RTP and RTCP packets.
  """
  @spec split_packets(binary(), [binary()], [binary()]) :: {[binary()], [binary()], binary()}
  def split_packets(
        <<"$", channel::8, size::16, packet::binary-size(size)-unit(8), rest::binary>>,
        rtsp_session,
        {rtp_packets, rtcp_packets}
      ) do
    if rem(channel, 2) == 0 do
      split_packets(rest, rtsp_session, {[packet | rtp_packets], rtcp_packets})
    else
      split_packets(rest, rtsp_session, {rtp_packets, [packet | rtcp_packets]})
    end
  end

  def split_packets(<<"RTSP", _rest::binary>> = data, rtsp_session, {rtp_packets, rtcp_packets}) do
    case RTSP.Response.verify_content_length(data) do
      {:ok, _expected_length, _actual_length} ->
        handle_rtsp_response(rtsp_session, data)
        {Enum.reverse(rtp_packets), Enum.reverse(rtcp_packets), <<>>}

      {:error, expected_length, actual_length} when actual_length > expected_length ->
        rest_length = actual_length - expected_length
        rtsp_message_length = byte_size(data) - rest_length

        <<rtsp_message::binary-size(rtsp_message_length)-unit(8), rest::binary>> = data
        handle_rtsp_response(rtsp_session, rtsp_message)
        split_packets(rest, rtsp_session, {rtp_packets, rtcp_packets})

      {:error, expected_length, actual_length} when actual_length <= expected_length ->
        {Enum.reverse(rtp_packets), Enum.reverse(rtcp_packets), data}
    end
  end

  def split_packets(rest, _rtsp_session, _packets) when byte_size(rest) >= @max_buffer_size do
    raise """
    Buffered rtp data exceeded the allowed limit
    Limit: #{@max_buffer_size} bytes.
    Current buffer size: #{byte_size(rest)} bytes
    """
  end

  def split_packets(rest, _rtsp_session, {rtp_packets, rtcp_packets}) do
    {Enum.reverse(rtp_packets), Enum.reverse(rtcp_packets), rest}
  end

  defp handle_rtsp_response(nil, response), do: :ok

  defp handle_rtsp_response(session, response) do
    case RTSP.handle_response(session, response) do
      {:ok, %RTSP.Response{status: 200}} ->
        :ok

      {:ok, %RTSP.Response{status: 401}} ->
        RTSP.get_parameter_no_response(session)

      {:error, reason} ->
        raise """
        An error occurred while parsing rtsp response
        Response: #{inspect(response)}
        Reason: #{inspect(reason)}
        """
    end
  end
end
