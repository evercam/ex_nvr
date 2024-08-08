defmodule ExNVR.RTSP.PacketSplitterTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.RTSP.Source.PacketSplitter

  test "split stream to rtp packets" do
    assert {rtp_packets, <<>>} =
             File.stream!("test/fixtures/packets.bin", [], 1024)
             |> Enum.reduce({[], <<>>}, fn data, {rtp_packets, unprocessed_data} ->
               {packets, _rtcp_packets, unprocessed_data} =
                 PacketSplitter.split_packets(unprocessed_data <> data, nil, {[], []})

               {rtp_packets ++ packets, unprocessed_data}
             end)

    assert length(rtp_packets) == 190
  end
end
