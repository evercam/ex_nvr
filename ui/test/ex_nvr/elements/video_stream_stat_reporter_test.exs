defmodule ExNVR.Elements.VideoStreamStatReporterTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Elements.VideoStreamStatReporter

  @ctx %{}

  setup do
    assert {_actions, state} =
             VideoStreamStatReporter.handle_init(@ctx, %VideoStreamStatReporter{
               device_id: UUID.uuid4()
             })

    %{state: state}
  end

  test "init video stream stats", %{state: state} do
    assert %{
             stream: :high,
             resolution: nil,
             profile: nil,
             elapsed_time: 0,
             total_bytes: 0,
             total_frames: 0,
             frames_since_last_keyframe: 0,
             avg_bitrate: 0,
             avg_fps: 0,
             avg_gop_size: nil,
             gop_size: 0
           } = state
  end

  test "get resolution and profile", %{state: state} do
    assert {_actions, %{resolution: {640, 480}, profile: :main}} =
             VideoStreamStatReporter.handle_stream_format(
               :input,
               %Membrane.H264{width: 640, height: 480, profile: :main},
               @ctx,
               state
             )
  end

  test "get stream stats", %{state: state} do
    state = %{state | start_time: Membrane.Time.monotonic_time() - Membrane.Time.seconds(4)}

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

    assert %{
             total_frames: 10,
             total_bytes: 1040,
             avg_gop_size: 4.5,
             gop_size: 5,
             resolution: nil,
             profile: nil
           } = state

    assert_in_delta(state.avg_fps, 2.5, 0.1)
    assert_in_delta(state.avg_bitrate, 2080, 30)
  end
end
