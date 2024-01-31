defmodule ExNVR.Pipeline.Source.RTSPPipelineTest do
  @moduledoc false

  use ExUnit.Case, async: false

  require Membrane.Pad

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec

  alias ExNVR.RTSP.Transport.Fake
  alias Membrane.{Pad, Testing}

  @rtsp_uri "rtsp://example.com:554/video1"

  test "RTSP source element" do
    Application.put_env(
      :ex_nvr,
      :tcp_socket_resolver,
      &Fake.establish_session_with_media_packets/2
    )

    pipeline_pid = start_pipeline(@rtsp_uri)

    assert_pipeline_notified(
      pipeline_pid,
      :source,
      {:new_track, ssrc, %{type: :video, encoding: :H264}}
    )

    Testing.Pipeline.execute_actions(pipeline_pid,
      spec: [get_child(:source) |> via_out(Pad.ref(:output, ssrc)) |> child(:sink, Testing.Sink)]
    )

    assert_sink_stream_format(pipeline_pid, :sink, %Membrane.H264{alignment: :au})
    assert_sink_buffer(pipeline_pid, :sink, %Membrane.Buffer{payload: _payload})

    Testing.Pipeline.terminate(pipeline_pid)
  end

  defp start_pipeline(stream_uri) do
    Testing.Pipeline.start_supervised!(
      spec: [
        child(:source, %ExNVR.Pipeline.Source.RTSP{stream_uri: stream_uri})
      ]
    )
  end
end
