defmodule ExNVR.Elements.VideoBuffererTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Elements.VideoBufferer

  @ctx %{}
  @topic "trigger_recording:test-123"
  @stream_format %Membrane.H264{width: 1920, height: 1080, alignment: :au}

  # --- Helpers ---

  defp init(opts \\ []) do
    options = %VideoBufferer{
      topic: Keyword.get(opts, :topic, @topic),
      limit: Keyword.get(opts, :limit, {:keyframes, 3}),
      event_timeout: Keyword.get(opts, :event_timeout, 30_000)
    }

    {[], state} = VideoBufferer.handle_init(@ctx, options)
    state
  end

  defp h264_buffer(opts \\ []) do
    key_frame? = Keyword.get(opts, :key_frame?, false)
    payload = Keyword.get(opts, :payload, :crypto.strong_rand_bytes(100))
    pts = Keyword.get(opts, :pts, nil)

    %Membrane.Buffer{
      payload: payload,
      pts: pts,
      metadata: %{h264: %{key_frame?: key_frame?}}
    }
  end

  defp h265_buffer(opts) do
    key_frame? = Keyword.get(opts, :key_frame?, false)
    payload = Keyword.get(opts, :payload, :crypto.strong_rand_bytes(100))
    pts = Keyword.get(opts, :pts, nil)

    %Membrane.Buffer{
      payload: payload,
      pts: pts,
      metadata: %{h265: %{key_frame?: key_frame?}}
    }
  end

  defp send_buffers(state, buffers) do
    Enum.reduce(buffers, {[], state}, fn buffer, {_prev_actions, state} ->
      VideoBufferer.handle_buffer(:input, buffer, @ctx, state)
    end)
  end

  defp send_event(state, name \\ "recording_triggered") do
    VideoBufferer.handle_info({:event, name}, @ctx, state)
  end

  defp send_timeout(state) do
    VideoBufferer.handle_info(:event_timeout, @ctx, state)
  end

  defp output_buffers(actions) do
    case Keyword.get(actions, :buffer) do
      {:output, buffers} when is_list(buffers) -> buffers
      {:output, buffer} -> [buffer]
      nil -> []
    end
  end

  defp has_discontinuity?(actions) do
    case Keyword.get(actions, :event) do
      {:output, %Membrane.Event.Discontinuity{}} -> true
      _ -> false
    end
  end

  # --- Stream format ---

  test "forwards stream format" do
    state = init()
    {actions, state} = VideoBufferer.handle_stream_format(:input, @stream_format, @ctx, state)

    assert [stream_format: {:output, @stream_format}] = actions
    assert state.stream_format == @stream_format
  end

  # --- Buffering mode basics ---

  test "frames are held in buffering mode, not forwarded" do
    state = init()

    buffers = [
      h264_buffer(key_frame?: true),
      h264_buffer(),
      h264_buffer()
    ]

    {actions, state} = send_buffers(state, buffers)

    assert actions == []
    assert state.mode == :buffering
    assert :queue.len(state.buffer) == 3
  end

  test "tracks keyframe count correctly" do
    state = init()

    buffers = [
      h264_buffer(key_frame?: true),
      h264_buffer(),
      h264_buffer(),
      h264_buffer(key_frame?: true),
      h264_buffer()
    ]

    {_actions, state} = send_buffers(state, buffers)

    assert state.keyframe_count == 2
  end

  test "tracks buffer byte size correctly" do
    state = init()
    payload1 = :crypto.strong_rand_bytes(200)
    payload2 = :crypto.strong_rand_bytes(300)

    buffers = [
      h264_buffer(key_frame?: true, payload: payload1),
      h264_buffer(payload: payload2)
    ]

    {_actions, state} = send_buffers(state, buffers)

    assert state.buffer_size == 500
  end

  # --- Keyframe eviction ---

  test "keyframe limit evicts oldest coded video sequence" do
    state = init(limit: {:keyframes, 2})

    # CVS 1: keyframe + 2 frames
    kf1 = h264_buffer(key_frame?: true, payload: <<1>>)
    f1a = h264_buffer(payload: <<2>>)
    f1b = h264_buffer(payload: <<3>>)

    # CVS 2: keyframe + 1 frame
    kf2 = h264_buffer(key_frame?: true, payload: <<4>>)
    f2a = h264_buffer(payload: <<5>>)

    # CVS 3: adding this exceeds limit of 2 keyframes
    kf3 = h264_buffer(key_frame?: true, payload: <<6>>)
    f3a = h264_buffer(payload: <<7>>)

    buffers = [kf1, f1a, f1b, kf2, f2a, kf3, f3a]
    {_actions, state} = send_buffers(state, buffers)

    # drop_oldest_cvs removes the entire oldest CVS (keyframe + its trailing
    # non-keyframes up to the next keyframe). CVS 1 = [kf1, f1a, f1b] is gone.
    assert state.keyframe_count == 2
    remaining = :queue.to_list(state.buffer)
    assert Enum.map(remaining, & &1.payload) == [<<4>>, <<5>>, <<6>>, <<7>>]
  end

  test "keyframe limit of 1 evicts until only one keyframe remains" do
    state = init(limit: {:keyframes, 1})

    kf1 = h264_buffer(key_frame?: true, payload: <<1>>)
    f1 = h264_buffer(payload: <<2>>)
    kf2 = h264_buffer(key_frame?: true, payload: <<3>>)
    f2 = h264_buffer(payload: <<4>>)

    {_actions, state} = send_buffers(state, [kf1, f1, kf2, f2])

    # kf1 + f1 evicted as a complete CVS when kf2 pushed (kf_count 2 > 1)
    assert state.keyframe_count == 1
    remaining = :queue.to_list(state.buffer)
    assert Enum.map(remaining, & &1.payload) == [<<3>>, <<4>>]
  end

  # --- Bytes eviction ---

  test "bytes limit evicts oldest frames to stay within limit" do
    state = init(limit: {:bytes, 250})

    buffers = [
      h264_buffer(key_frame?: true, payload: :crypto.strong_rand_bytes(100)),
      h264_buffer(payload: :crypto.strong_rand_bytes(100)),
      h264_buffer(payload: :crypto.strong_rand_bytes(100))
    ]

    {_actions, state} = send_buffers(state, buffers)

    # 300 bytes total > 250 limit, so oldest frame(s) dropped
    assert state.buffer_size <= 250
    assert :queue.len(state.buffer) == 2
  end

  test "bytes limit drops multiple frames if needed" do
    state = init(limit: {:bytes, 100})

    buffers = [
      h264_buffer(key_frame?: true, payload: :crypto.strong_rand_bytes(80)),
      h264_buffer(payload: :crypto.strong_rand_bytes(80)),
      h264_buffer(payload: :crypto.strong_rand_bytes(80)),
      h264_buffer(payload: :crypto.strong_rand_bytes(80))
    ]

    {_actions, state} = send_buffers(state, buffers)

    # 320 bytes total, limit 100 — only last frame should remain
    assert state.buffer_size <= 100
    assert :queue.len(state.buffer) == 1
  end

  # --- Seconds eviction ---

  test "seconds limit evicts frames older than the duration" do
    state = init(limit: {:seconds, 5})

    buffers = [
      h264_buffer(key_frame?: true, pts: Membrane.Time.seconds(0)),
      h264_buffer(pts: Membrane.Time.seconds(2)),
      h264_buffer(pts: Membrane.Time.seconds(4)),
      h264_buffer(pts: Membrane.Time.seconds(6)),
      h264_buffer(pts: Membrane.Time.seconds(8))
    ]

    {_actions, state} = send_buffers(state, buffers)

    # Span of 8 seconds > 5 limit, oldest frames dropped
    remaining = :queue.to_list(state.buffer)

    oldest_pts = hd(remaining).pts
    newest_pts = List.last(remaining).pts
    span = Membrane.Time.as_seconds(newest_pts - oldest_pts, :round)
    assert span <= 5
  end

  test "seconds limit allows frames within the duration" do
    state = init(limit: {:seconds, 10})

    buffers = [
      h264_buffer(key_frame?: true, pts: Membrane.Time.seconds(0)),
      h264_buffer(pts: Membrane.Time.seconds(2)),
      h264_buffer(pts: Membrane.Time.seconds(4))
    ]

    {_actions, state} = send_buffers(state, buffers)

    # Span of 4 seconds < 10 limit, all frames kept
    assert :queue.len(state.buffer) == 3
  end

  # --- Event triggers flush ---

  test "event flushes buffer from first keyframe and switches to forwarding" do
    state = init()

    kf1 = h264_buffer(key_frame?: true, payload: <<1>>)
    f1 = h264_buffer(payload: <<2>>)
    kf2 = h264_buffer(key_frame?: true, payload: <<3>>)
    f2 = h264_buffer(payload: <<4>>)

    {_actions, state} = send_buffers(state, [kf1, f1, kf2, f2])
    assert state.mode == :buffering

    {actions, state} = send_event(state)

    # Should flush from first keyframe (kf1) onwards — the full pre-roll
    flushed = output_buffers(actions)
    assert length(flushed) == 4
    assert Enum.map(flushed, & &1.payload) == [<<1>>, <<2>>, <<3>>, <<4>>]
    assert state.mode == :forwarding
  end

  test "event with empty buffer switches to forwarding with no output" do
    state = init()
    {actions, state} = send_event(state)

    assert output_buffers(actions) == []
    assert state.mode == :forwarding
  end

  test "event with only non-keyframes in buffer flushes nothing" do
    state = init()

    # No keyframe in buffer — can't start a decodable stream, so nothing flushed.
    f1 = h264_buffer(payload: <<1>>)
    f2 = h264_buffer(payload: <<2>>)

    {_actions, state} = send_buffers(state, [f1, f2])
    {actions, state} = send_event(state)

    flushed = output_buffers(actions)
    assert length(flushed) == 0
    assert state.mode == :forwarding
  end

  # --- Forwarding mode ---

  test "frames pass through immediately in forwarding mode" do
    state = init()
    {_actions, state} = send_event(state)
    assert state.mode == :forwarding

    buffer = h264_buffer(key_frame?: true, payload: <<99>>)
    {actions, state} = VideoBufferer.handle_buffer(:input, buffer, @ctx, state)

    forwarded = output_buffers(actions)
    assert length(forwarded) == 1
    assert hd(forwarded).payload == <<99>>
    assert state.mode == :forwarding
  end

  # --- Event timeout ---

  test "timeout in forwarding mode sends discontinuity and returns to buffering" do
    state = init()
    {_actions, state} = send_event(state)
    assert state.mode == :forwarding

    {actions, state} = send_timeout(state)

    assert has_discontinuity?(actions)
    assert state.mode == :buffering
    assert state.timeout_ref == nil
    assert :queue.is_empty(state.buffer)
    assert state.buffer_size == 0
    assert state.keyframe_count == 0
  end

  test "timeout in buffering mode is a no-op" do
    state = init()
    assert state.mode == :buffering

    {actions, state} = send_timeout(state)

    assert actions == []
    assert state.mode == :buffering
  end

  # --- Recurring events extend forwarding ---

  test "recurring events reset the timeout to keep recording going" do
    state = init(event_timeout: 100)

    # First event: start forwarding
    {_actions, state} = send_event(state)
    assert state.mode == :forwarding
    first_ref = state.timeout_ref

    # Second event while still forwarding: should reset timer
    {actions, state} = send_event(state)
    assert actions == []
    assert state.mode == :forwarding
    assert state.timeout_ref != first_ref
  end

  test "recording continues as long as events keep arriving" do
    state = init(event_timeout: 50)

    # Start forwarding
    {_actions, state} = send_event(state)
    assert state.mode == :forwarding

    # Simulate several events arriving, each before the timeout
    state =
      Enum.reduce(1..5, state, fn _i, state ->
        # Send another event (which resets timer)
        {_actions, state} = send_event(state)
        assert state.mode == :forwarding

        # Forward some frames in between
        buf = h264_buffer(payload: <<42>>)
        {actions, state} = VideoBufferer.handle_buffer(:input, buf, @ctx, state)
        assert output_buffers(actions) != []

        state
      end)

    assert state.mode == :forwarding

    # Now let it time out
    {actions, state} = send_timeout(state)
    assert has_discontinuity?(actions)
    assert state.mode == :buffering
  end

  # --- Full cycle: buffer → forward → timeout → buffer again ---

  test "full cycle: buffer, event flush, forward, timeout, buffer again" do
    state = init(limit: {:keyframes, 2})

    # Phase 1: buffering
    kf1 = h264_buffer(key_frame?: true, payload: <<1>>)
    f1 = h264_buffer(payload: <<2>>)
    {_actions, state} = send_buffers(state, [kf1, f1])
    assert state.mode == :buffering

    # Phase 2: event flushes and starts forwarding
    {actions, state} = send_event(state)
    flushed = output_buffers(actions)
    assert length(flushed) == 2
    assert state.mode == :forwarding

    # Phase 3: frames pass through
    live_frame = h264_buffer(key_frame?: true, payload: <<10>>)
    {actions, _state} = VideoBufferer.handle_buffer(:input, live_frame, @ctx, state)
    assert output_buffers(actions) |> length() == 1

    # Phase 4: timeout returns to buffering
    {actions, state} = send_timeout(state)
    assert has_discontinuity?(actions)
    assert state.mode == :buffering
    assert :queue.is_empty(state.buffer)

    # Phase 5: new frames are buffered again
    kf2 = h264_buffer(key_frame?: true, payload: <<20>>)
    f2 = h264_buffer(payload: <<21>>)
    {actions, state} = send_buffers(state, [kf2, f2])
    assert actions == []
    assert state.mode == :buffering
    assert :queue.len(state.buffer) == 2
  end

  # --- H265 support ---

  test "works with H265 buffers" do
    state = init(limit: {:keyframes, 2})

    kf1 = h265_buffer(key_frame?: true, payload: <<1>>)
    f1 = h265_buffer(payload: <<2>>)
    kf2 = h265_buffer(key_frame?: true, payload: <<3>>)
    f2 = h265_buffer(payload: <<4>>)

    {_actions, state} = send_buffers(state, [kf1, f1, kf2, f2])
    assert state.keyframe_count == 2

    # Trigger event — should flush from first keyframe (full pre-roll)
    {actions, state} = send_event(state)
    flushed = output_buffers(actions)
    assert length(flushed) == 4
    assert Enum.map(flushed, & &1.payload) == [<<1>>, <<2>>, <<3>>, <<4>>]
    assert state.mode == :forwarding
  end

  # --- Edge cases ---

  test "single keyframe in buffer is flushed on event" do
    state = init()

    kf = h264_buffer(key_frame?: true, payload: <<1>>)
    {_actions, state} = send_buffers(state, [kf])

    {actions, state} = send_event(state)
    flushed = output_buffers(actions)
    assert length(flushed) == 1
    assert hd(flushed).payload == <<1>>
    assert state.mode == :forwarding
  end

  test "unrelated messages are ignored" do
    state = init()
    {actions, new_state} = VideoBufferer.handle_info(:something_random, @ctx, state)
    assert actions == []
    assert new_state == state
  end

  test "iodata payloads are sized correctly for bytes limit" do
    state = init(limit: {:bytes, 200})

    # iodata payload (list of binaries)
    iodata = [<<1, 2, 3>>, <<4, 5, 6, 7, 8>>]

    buffers = [
      h264_buffer(key_frame?: true, payload: :crypto.strong_rand_bytes(100)),
      h264_buffer(payload: :crypto.strong_rand_bytes(100)),
      %Membrane.Buffer{
        payload: iodata,
        metadata: %{h264: %{key_frame?: false}}
      }
    ]

    {_actions, state} = send_buffers(state, buffers)

    # 100 + 100 + 8 = 208 > 200, should evict
    assert state.buffer_size <= 200
  end

  test "multiple eviction cycles for keyframes" do
    # limit of 1 keyframe, push 4 CVSs
    state = init(limit: {:keyframes, 1})

    buffers =
      for i <- 1..4 do
        [
          h264_buffer(key_frame?: true, payload: <<i, 0>>),
          h264_buffer(payload: <<i, 1>>)
        ]
      end
      |> List.flatten()

    {_actions, state} = send_buffers(state, buffers)

    # Each eviction drops an entire CVS (keyframe + trailing non-keyframes).
    # After 4 CVSs with limit 1: only the latest CVS remains.
    assert state.keyframe_count == 1
    remaining = :queue.to_list(state.buffer)
    assert Enum.map(remaining, & &1.payload) == [<<4, 0>>, <<4, 1>>]
  end

  test "bytes eviction updates keyframe count correctly" do
    state = init(limit: {:bytes, 100})

    # A keyframe that gets evicted should decrement the keyframe count
    buffers = [
      h264_buffer(key_frame?: true, payload: :crypto.strong_rand_bytes(60)),
      h264_buffer(key_frame?: true, payload: :crypto.strong_rand_bytes(60)),
      h264_buffer(payload: :crypto.strong_rand_bytes(60))
    ]

    {_actions, state} = send_buffers(state, buffers)

    # Total would be 180 > 100, frames dropped from front
    # The keyframe_count should match what's actually in the buffer
    remaining = :queue.to_list(state.buffer)

    actual_kf_count =
      Enum.count(remaining, fn buf ->
        Map.has_key?(buf.metadata, :h264) and buf.metadata.h264.key_frame?
      end)

    assert state.keyframe_count == actual_kf_count
  end
end
