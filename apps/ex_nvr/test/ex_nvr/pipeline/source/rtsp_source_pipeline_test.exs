defmodule ExNVR.Pipeline.Source.RTSP.SourcePipelineTest do
  @moduledoc false

  use ExUnit.Case, async: false

  import Membrane.Testing.Assertions

  alias ExNVR.RTSP.Transport.Fake
  alias Membrane.Testing

  @moduletag :capture_log

  @rtsp_uri "rtsp://example.com:554/video1"

  test "receive media packets" do
    Application.put_env(
      :ex_nvr,
      :tcp_socket_resolver,
      &Fake.establish_session_with_media_packets/2
    )

    pipeline_pid = start_pipeline(@rtsp_uri)

    assert_pipeline_notified(pipeline_pid, :source, {:rtsp_setup_complete, _tracks})
    assert_sink_stream_format(pipeline_pid, :sink, %Membrane.RemoteStream{type: :packetized})
    assert_sink_buffer(pipeline_pid, :sink, %Membrane.Buffer{payload: <<1, 2, 3, 4, 5>>})
  end

  test "receive connection lost notification" do
    Application.put_env(
      :ex_nvr,
      :tcp_socket_resolver,
      &Fake.establish_session_with_media_error/2
    )

    pipeline_pid = start_pipeline(@rtsp_uri)

    assert_pipeline_notified(pipeline_pid, :source, {:rtsp_setup_complete, _tracks})
    assert_sink_stream_format(pipeline_pid, :sink, %Membrane.RemoteStream{type: :packetized})
    assert_pipeline_notified(pipeline_pid, :source, :connection_lost)
  end

  defp start_pipeline(stream_uri) do
    options = [
      module: ExNVR.RTSP.SourcePipeline,
      custom_args: [stream_uri: stream_uri]
    ]

    Testing.Pipeline.start_supervised!(options)
  end
end
