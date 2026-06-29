defmodule ExNVR.Hls.ProcessorTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.HLS.Processor

  describe "add query params" do
    test "to master manifest file" do
      in_file = "../../fixtures/hls/index.m3u8" |> Path.expand(__DIR__)
      ref_file = "../../fixtures/hls/ref_index.m3u8" |> Path.expand(__DIR__)

      perform_test(in_file, ref_file, :playlist)
    end

    test "to manifest file with segment" do
      in_file = "../../fixtures/hls/live_main_stream.m3u8" |> Path.expand(__DIR__)
      ref_file = "../../fixtures/hls/ref_live_main_stream.m3u8" |> Path.expand(__DIR__)

      perform_test(in_file, ref_file, :media_playlist)
    end
  end

  describe "delete stream" do
    test "from master manifest file" do
      expected_result =
        """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-INDEPENDENT-SEGMENTS
        #EXT-X-STREAM-INF:BANDWIDTH=1916270,CODECS="avc1.42e00a"
        live_main_stream.m3u8
        """

      in_file = "../../fixtures/hls/index.m3u8" |> Path.expand(__DIR__)
      assert expected_result == Processor.delete_stream(File.read!(in_file), "live_sub_stream")
    end

    test "when stream does not exists" do
      in_file = "../../fixtures/hls/index.m3u8" |> Path.expand(__DIR__)
      assert File.read!(in_file) == Processor.delete_stream(File.read!(in_file), "random_stream")
    end
  end

  defp perform_test(in_file, ref_file, playlist_type) do
    params = [stream_id: "my_stream_+_id", device_id: "first-device"]

    processed_manifest_file =
      Processor.add_query_params(File.read!(in_file), playlist_type, params)

    assert File.read!(ref_file) == processed_manifest_file
  end
end
