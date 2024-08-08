defmodule ExNVR.RTSP.ParserTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.RTSP.Parser
  alias ExRTP.Packet
  alias Membrane.{Buffer, H265}

  @hevc_fixture "test/fixtures/hevc_packets.bin"
  @hevc_reference "test/fixtures/reference_frame.h265"

  test "parse hevc packets" do
    rtp_packets =
      for <<size::32, packet::binary-size(size) <- File.read!(@hevc_fixture)>>, do: packet

    # We add the first rtp packet to force the parser
    # to output the access unit.
    rtp_packets = rtp_packets ++ [hd(rtp_packets)]

    assert {buffers, parser} =
             rtp_packets
             |> Enum.map(fn packet ->
               {:ok, packet} = Packet.decode(packet)
               packet
             end)
             |> Enum.flat_map_reduce(Parser.H265.init([]), fn packet, parser ->
               {:ok, {buffers, parser}} = Parser.H265.handle_packet(packet, parser)
               {buffers, parser}
             end)

    reference_data = File.read!(@hevc_reference)
    assert [%H265{width: 1920, height: 1080}, %Buffer{payload: ^reference_data}] = buffers

    assert map_size(parser.vps) == 1
    assert map_size(parser.sps) == 1
    assert map_size(parser.pps) == 1
  end
end
