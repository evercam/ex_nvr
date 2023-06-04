defmodule ExNVR.Elements.SegmenterTest do
  @moduledoc false
  use ExUnit.Case

  alias ExNVR.Elements.Segmenter
  alias ExNVR.Elements.Segmenter.Segment
  alias Membrane.{Buffer, Event, H264, Pad}

  require Membrane.Pad

  @input_stream_format %H264{alignment: :au, width: 1080, height: 720, profile: :baseline}

  test "ignore non keyframe buffers when starting" do
    state = init_element()
    assert {[], ^state} = Segmenter.handle_process(:input, build_buffer(10), %{}, state)
  end

  describe "First keyframe encountered" do
    test "is buffered and new segment event is sent" do
      state = init_element()
      assert {[], ^state} = Segmenter.handle_process(:input, build_buffer(10), %{}, state)

      buffer = build_buffer(10, true, 1_000)

      assert {[notify_parent: {:new_media_segment, _}], %{buffer: [^buffer]}} =
               Segmenter.handle_process(:input, buffer, %{}, state)
    end

    test "subsequent buffers are buffered if output pad is not linked" do
      state = init_element()

      buffer1 = build_buffer(10, true, 1_000)
      buffer2 = build_buffer(10, true, 2_000)

      assert {[notify_parent: {:new_media_segment, _}], %{buffer: [^buffer1]} = state} =
               Segmenter.handle_process(:input, buffer1, %{}, state)

      assert {[], %{buffer: [^buffer2, ^buffer1]}} =
               Segmenter.handle_process(:input, buffer2, %{}, state)
    end
  end

  describe "output pad is linked" do
    test "buffered events are sent" do
      state = init_element()

      buffer1 = build_buffer(10, true, 1_000)
      buffer2 = build_buffer(10, true, 1_000)

      assert {_, state} = Segmenter.handle_process(:input, buffer1, %{}, state)
      assert {_, state} = Segmenter.handle_process(:input, buffer1, %{}, state)

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
               Segmenter.handle_process(:input, buffer, %{}, %{
                 state
                 | buffer?: false,
                   start_time: 0,
                   last_buffer_pts: 0
               })
    end

    test "new segment is created when target duration is reached" do
      state = init_element()

      state =
        Map.merge(state, %{
          start_time: Membrane.Time.vm_time(),
          buffer?: false,
          buffer: [build_buffer(10, true, 0)],
          last_buffer_pts: 0
        })

      pad = Pad.ref(:output, state.start_time)

      buffer1 = build_buffer(10, false, Membrane.Time.milliseconds(1500))
      buffer2 = build_buffer(10, false, Membrane.Time.milliseconds(2300))
      buffer3 = build_buffer(10, true, Membrane.Time.milliseconds(2800))

      assert {_, state} = Segmenter.handle_process(:input, buffer1, %{}, state)
      assert {_, state} = Segmenter.handle_process(:input, buffer2, %{}, state)

      assert {[
                end_of_stream: ^pad,
                notify_parent: {:new_media_segment, _},
                notify_parent: {:completed_segment, {_, %Segment{}, false}}
              ], %{buffer: [^buffer3]}} = Segmenter.handle_process(:input, buffer3, %{}, state)
    end
  end

  test "receive discontinuity event will flush the current segment" do
    state = init_element()

    assert {[], ^state} = Segmenter.handle_event(:input, %Event.Discontinuity{}, %{}, state)

    state =
      Map.merge(state, %{
        start_time: Membrane.Time.vm_time(),
        buffer?: false,
        buffer: [build_buffer(10, true, 0), build_buffer(10, false, 1000)],
        last_buffer_pts: 1000
      })

    pad = Pad.ref(:output, state.start_time)

    assert {[
              end_of_stream: ^pad,
              notify_parent: {:completed_segment, {_, %Segment{}, true}}
            ],
            %{buffer: [], current_segment_duration: 0, start_time: nil}} =
             Segmenter.handle_event(:input, %Event.Discontinuity{}, %{}, state)
  end

  defp init_element() do
    assert {[], state} =
             Segmenter.handle_init(%{}, %Segmenter{
               segment_duration: 2
             })

    assert {[], %{stream_format: @input_stream_format} = state} =
             Segmenter.handle_stream_format(:input, @input_stream_format, %{}, state)

    state
  end

  defp build_buffer(payload_size, keyframe? \\ false, pts \\ nil) do
    %Buffer{
      payload: :binary.copy(<<1>>, payload_size),
      metadata: %{h264: %{key_frame?: keyframe?}},
      pts: pts
    }
  end
end
