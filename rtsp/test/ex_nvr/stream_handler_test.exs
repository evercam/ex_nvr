defmodule ExNVR.RTSP.StreamHandlerTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.RTSP.Source.{PacketSplitter, StreamHandler}
  alias Membrane.H264

  @h264_fixture "test/fixtures/packets.bin"

  test "parse h264 packets" do
    packets = get_rtp_packets(@h264_fixture)

    stream_handler = %StreamHandler{
      parser_mod: ExNVR.RTSP.Parser.H264,
      parser_state: ExNVR.RTSP.Parser.H264.init([])
    }

    assert {buffers, _handler} =
             Enum.map(packets, fn packet ->
               {:ok, packet} = ExRTP.Packet.decode(packet)
               packet
             end)
             |> Enum.reduce({[], stream_handler}, fn packet, {buffers, handler} ->
               {new_buffers, handler} = StreamHandler.handle_packet(handler, packet, DateTime.utc_now())
               {buffers ++ new_buffers, handler}
             end)

    assert length(buffers) == 24
    assert [%H264{} = stream_format | _rest] = buffers

    assert %H264{
             width: 640,
             height: 480,
             profile: :main,
             alignment: :au
           } = stream_format
  end

  defp get_rtp_packets(file) do
    {rtp_packets, <<>>} =
      File.stream!(file, [], 1024)
      |> Enum.reduce({[], <<>>}, fn data, {rtp_packets, unprocessed_data} ->
        {packets, _rtcp_packets, unprocessed_data} =
          PacketSplitter.split_packets(unprocessed_data <> data, nil, {[], []})

        {rtp_packets ++ packets, unprocessed_data}
      end)

    rtp_packets
  end
end
