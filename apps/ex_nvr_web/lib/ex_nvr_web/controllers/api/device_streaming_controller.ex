defmodule ExNVRWeb.API.DeviceStreamingController do
  @moduledoc false

  use ExNVRWeb, :controller

  require Logger

  alias ExNVR.Pipeline

  @hls_live_directory "/home/ghilas/p/Evercam/ex_nvr/data/hls"
  @hls_live_streaming_id UUID.uuid4()

  def hls_stream(conn, _params) do
    :ok = Pipeline.start_hls_streaming(@hls_live_streaming_id)
    ExNVRWeb.HlsStreamingMonitor.register(@hls_live_streaming_id, &Pipeline.stop_hls_streaming/0)
    send_file(conn, 200, Path.join(@hls_live_directory, "index.m3u8"))
  end

  def hls_stream_segment(conn, %{"segment_name" => segment_name}) do
    # segment names are in the following format <segment_name>_<id>.<extension>
    # this is a temporary measure until Membrane HLS plugin supports query params
    # in segment files
    if not String.ends_with?(segment_name, ".m3u8") do
      id = String.split(segment_name, "_") |> hd()
      ExNVRWeb.HlsStreamingMonitor.update_last_access_time(id)
    end

    send_file(conn, 200, Path.join(@hls_live_directory, segment_name))
  end
end
