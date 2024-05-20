defmodule ExNVR.Elements.VideoStreamStatReporterTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Elements.VideoStreamStatReporter

  @ctx %{}

  test "init video stream stats" do
    {_actions, state} =
      VideoStreamStatReporter.handle_init(@ctx, %VideoStreamStatReporter{
        report_interval: Membrane.Time.seconds(1)
      })

    assert state == %{
             report_interval: Membrane.Time.seconds(1),
             resolution: nil,
             profile: nil,
             elapsed_time: 0,
             total_bytes: 0,
             total_frames: 0,
             frames_since_last_keyframe: 0,
             avg_gop_size: nil
           }
  end

  test "get resolution and profile" do
    assert {_actions, state} =
             VideoStreamStatReporter.handle_init(@ctx, %VideoStreamStatReporter{
               report_interval: Membrane.Time.seconds(1)
             })

    assert {_actions, %{resolution: {640, 480}, profile: :main}} =
             VideoStreamStatReporter.handle_stream_format(
               :input,
               %Membrane.H264{width: 640, height: 480, profile: :main},
               @ctx,
               state
             )
  end

  test "get stream stats" do
    assert {_actions, state} =
             VideoStreamStatReporter.handle_init(@ctx, %VideoStreamStatReporter{
               report_interval: Membrane.Time.seconds(4)
             })

    buffers = [
      %Membrane.Buffer{payload: <<10::100*8>>, metadata: %{h264: %{key_frame?: true}}},
      %Membrane.Buffer{payload: <<10::150*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::50*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::100*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::130*8>>, metadata: %{h264: %{key_frame?: true}}},
      %Membrane.Buffer{payload: <<10::130*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::110*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::90*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::80*8>>, metadata: %{h264: %{key_frame?: false}}},
      %Membrane.Buffer{payload: <<10::100*8>>, metadata: %{h264: %{key_frame?: true}}}
    ]

    state =
      Enum.reduce(buffers, state, fn buffer, state ->
        assert {_actions, state} =
                 VideoStreamStatReporter.handle_buffer(:input, buffer, @ctx, state)

        state
      end)

    assert {[notify_parent: {:stats, stats}], _state} =
             VideoStreamStatReporter.handle_tick(:report_stats, @ctx, state)

    assert %{
             avg_bitrate: 2080,
             avg_fps: 2.5,
             avg_gop_size: 4.5,
             resolution: nil,
             profile: nil
           } = stats
  end
end
