defmodule ExNVR.Pipeline.Output.Storage.SegmenterTest do
  @moduledoc false
  use ExUnit.Case

  alias ExNVR.Pipeline.Output.Storage.Segmenter
  alias ExNVR.Pipeline.Output.Storage.Segmenter.Segment
  alias Membrane.{Buffer, Event, H264, Pad}

  require Membrane.Pad

  @input_stream_format %H264{alignment: :au, width: 1080, height: 720, profile: :baseline}

  test "ignore non keyframe buffers when starting" do
    state = init_element()
    assert {[], ^state} = Segmenter.handle_buffer(:input, build_buffer(10), %{}, state)
  end

  describe "First keyframe encountered" do
    test "is buffered and new segment event is sent" do
      state = init_element()
      assert {[], ^state} = Segmenter.handle_buffer(:input, build_buffer(10), %{}, state)

      buffer = build_buffer(10, true, 1_000)

      assert {[notify_parent: {:new_media_segment, _, :H264}], %{buffer: [^buffer]}} =
               Segmenter.handle_buffer(:input, buffer, %{}, state)
    end

    test "subsequent buffers are buffered if output pad is not linked" do
      state = init_element()

      buffer1 = build_buffer(10, true, 1_000)
      buffer2 = build_buffer(10, false, 2_000)

      assert {[notify_parent: {:new_media_segment, _, :H264}], %{buffer: [^buffer1]} = state} =
               Segmenter.handle_buffer(:input, buffer1, %{}, state)

      assert {[], %{buffer: [^buffer2, ^buffer1]}} =
               Segmenter.handle_buffer(:input, buffer2, %{}, state)
    end
  end

  describe "output pad is linked" do
    test "buffered events are sent" do
      state = init_element()

      buffer1 = build_buffer(10, true, 1_000)
      buffer2 = build_buffer(10, true, 1_000)

      assert {_, state} = Segmenter.handle_buffer(:input, buffer1, %{}, state)
      assert {_, state} = Segmenter.handle_buffer(:input, buffer1, %{}, state)

      pad = Pad.ref(:output, state.start_time)

      assert {[
                stream_format: {^pad, @input_stream_format},
                buffer: {^pad, ^buffer1},
                buffer: {^pad, ^buffer2}
              ], %{buffer?: false}} = Segmenter.handle_pad_added(pad, %{}, state)
    end

    test "new buffers are sent directly" do
      state = init_element()
      buffer = build_buffer(10, true, 1_000)

      assert {[buffer: {Pad.ref(:output, 0), ^buffer}], _state} =
               Segmenter.handle_buffer(:input, buffer, %{}, %{
                 state
                 | buffer?: false,
                   start_time: 0,
                   last_buffer_dts: 0,
                   segment: Segment.new(0)
               })
    end

    test "new segment is created when target duration is reached" do
      state = init_element()
      {_, state} = Segmenter.handle_buffer(:input, build_buffer(10, true, 0), %{}, state)

      pad = Pad.ref(:output, state.start_time)

      {_, state} = Segmenter.handle_pad_added(pad, %{}, state)

      buffer1 = build_buffer(10, false, Membrane.Time.milliseconds(1500))
      buffer2 = build_buffer(10, false, Membrane.Time.milliseconds(2300))
      buffer3 = build_buffer(10, true, Membrane.Time.milliseconds(2800))

      assert {[buffer: {^pad, ^buffer1}], state} =
               Segmenter.handle_buffer(:input, buffer1, %{}, state)

      assert {[buffer: {^pad, ^buffer2}], state} =
               Segmenter.handle_buffer(:input, buffer2, %{}, state)

      assert {[
                notify_parent: {:new_media_segment, _, :H264},
                end_of_stream: ^pad,
                notify_parent: {:completed_segment, {_, %Segment{}, false}}
              ], %{buffer: [^buffer3]}} = Segmenter.handle_buffer(:input, buffer3, %{}, state)
    end
  end

  test "receive discontinuity event will flush the current segment" do
    state = init_element()
    assert {[], ^state} = Segmenter.handle_event(:input, %Event.Discontinuity{}, %{}, state)

    {_, state} = Segmenter.handle_buffer(:input, build_buffer(10, true, 0), %{}, state)
    {_, state} = Segmenter.handle_buffer(:input, build_buffer(10, false, 1000), %{}, state)

    pad = Pad.ref(:output, state.start_time)
    {_, state} = Segmenter.handle_pad_added(pad, %{}, state)

    assert {[
              end_of_stream: ^pad,
              notify_parent: {:completed_segment, {_, %Segment{}, true}}
            ],
            %{buffer: [], segment: nil, start_time: nil}} =
             Segmenter.handle_event(:input, %Event.Discontinuity{}, %{}, state)
  end

  defp init_element() do
    assert {[], state} = Segmenter.handle_init(%{}, %Segmenter{target_duration: 2})

    assert {[], %{stream_format: @input_stream_format} = state} =
             Segmenter.handle_stream_format(:input, @input_stream_format, %{}, state)

    state
  end

  defp build_buffer(payload_size, keyframe? \\ false, dts \\ nil) do
    %Buffer{
      payload: :binary.copy(<<1>>, payload_size),
      metadata: %{h264: %{key_frame?: keyframe?}},
      dts: dts
    }
  end
end
