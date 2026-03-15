defmodule ExNVR.Elements.VideoBufferer do
  @moduledoc """
  Membrane Filter that buffers video frames and gates their flow to downstream
  elements based on events received via PubSub.

  Used in `:on_event` recording mode. When no event is active, frames are held
  in a circular buffer (up to `limit`). When an event arrives, the buffer is
  flushed (starting from the latest keyframe) and the filter switches to
  passthrough mode. After `event_timeout` ms with no new events, a
  `Membrane.Event.Discontinuity` is sent downstream and the filter returns to
  buffering mode.
  """

  use Membrane.Filter

  require ExNVR.Utils
  require Membrane.Logger

  alias ExNVR.Utils
  alias Membrane.{H264, H265}

  def_input_pad :input,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_output_pad :output,
    flow_control: :auto,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

  def_options(
    topic: [
      spec: String.t(),
      description: "PubSub topic to subscribe to for event signals"
    ],
    limit: [
      spec: {:keyframes, pos_integer()} | {:seconds, pos_integer()} | {:bytes, pos_integer()},
      default: {:keyframes, 3},
      description: "Circular-buffer eviction strategy"
    ],
    event_timeout: [
      spec: pos_integer(),
      default: 30_000,
      description: "Milliseconds of silence after the last event before returning to buffering"
    ]
  )

  @impl true
  def handle_init(_ctx, options) do
    state = %{
      topic: options.topic,
      limit: options.limit,
      event_timeout: options.event_timeout,
      mode: :buffering,
      buffer: :queue.new(),
      buffer_size: 0,
      keyframe_count: 0,
      timeout_ref: nil,
      stream_format: nil,
      frames_received: 0
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    Phoenix.PubSub.subscribe(ExNVR.PubSub, state.topic)
    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, stream_format}], %{state | stream_format: stream_format}}
  end

  # --- Forwarding mode: pass frames through ---
  @impl true
  def handle_buffer(:input, buffer, _ctx, %{mode: :forwarding} = state) do
    frames_received = state.frames_received + 1

    if rem(frames_received, 100) == 0 do
      Membrane.Logger.info("Forwarding stats: received=#{frames_received}, pts=#{inspect(buffer.pts)}")
    end

    {[buffer: {:output, buffer}], %{state | frames_received: frames_received}}
  end

  # --- Buffering mode: accumulate frames ---
  @impl true
  def handle_buffer(:input, buffer, _ctx, %{mode: :buffering} = state) do
    is_keyframe = Utils.keyframe(buffer)

    keyframe_count =
      if is_keyframe, do: state.keyframe_count + 1, else: state.keyframe_count

    queue = :queue.in(buffer, state.buffer)
    buffer_size = state.buffer_size + payload_size(buffer.payload)
    frames_received = state.frames_received + 1

    if rem(frames_received, 100) == 0 do
      Membrane.Logger.info(
        "Buffering stats: received=#{frames_received}, " <>
          "queued=#{:queue.len(queue)}, keyframes=#{keyframe_count}, " <>
          "pts=#{inspect(buffer.pts)}"
      )
    end

    state = %{
      state
      | buffer: queue,
        buffer_size: buffer_size,
        keyframe_count: keyframe_count,
        frames_received: frames_received
    }

    {[], evict(state)}
  end

  # --- Event received: flush buffer and switch to forwarding ---
  @impl true
  def handle_info({:event, _event_name}, _ctx, state) do
    state = reset_timeout(state)

    case state.mode do
      :forwarding ->
        {[], state}

      :buffering ->
        {buffers, state} = flush_from_keyframe(state)

        log_buffer_span(buffers)

        actions =
          if buffers == [] do
            []
          else
            [buffer: {:output, buffers}]
          end

        {actions, %{state | mode: :forwarding}}
    end
  end

  # --- Timeout: switch back to buffering, send discontinuity ---
  @impl true
  def handle_info(:event_timeout, _ctx, %{mode: :forwarding} = state) do
    Membrane.Logger.info("Event timeout reached, switching to buffering mode")

    state = %{
      state
      | mode: :buffering,
        timeout_ref: nil,
        buffer: :queue.new(),
        buffer_size: 0,
        keyframe_count: 0
    }

    {[event: {:output, %Membrane.Event.Discontinuity{}}], state}
  end

  @impl true
  def handle_info(:event_timeout, _ctx, state) do
    {[], %{state | timeout_ref: nil}}
  end

  @impl true
  def handle_info(_msg, _ctx, state) do
    {[], state}
  end

  # -- Private helpers --

  defp reset_timeout(state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)
    ref = Process.send_after(self(), :event_timeout, state.event_timeout)
    %{state | timeout_ref: ref}
  end

  defp flush_from_keyframe(state) do
    buffers = :queue.to_list(state.buffer)

    # Drop any orphaned non-keyframes at the front, then flush everything
    # from the first keyframe onwards — this is the full pre-roll.
    flushed = Enum.drop_while(buffers, fn buf -> not Utils.keyframe(buf) end)

    state = %{state | buffer: :queue.new(), buffer_size: 0, keyframe_count: 0}
    {flushed, state}
  end

  defp evict(%{limit: {:keyframes, max}} = state) when state.keyframe_count > max do
    state = drop_oldest_cvs(state)
    evict(state)
  end

  defp evict(%{limit: {:bytes, max}} = state) when state.buffer_size > max do
    state = drop_oldest_frame(state)
    evict(state)
  end

  defp evict(%{limit: {:seconds, max}} = state) do
    case {:queue.peek(state.buffer), :queue.peek_r(state.buffer)} do
      {{:value, oldest}, {:value, newest}} ->
        oldest_ts = buffer_pts(oldest)
        newest_ts = buffer_pts(newest)

        if oldest_ts && newest_ts &&
             Membrane.Time.as_seconds(newest_ts - oldest_ts, :round) > max do
          state = drop_oldest_frame(state)
          evict(state)
        else
          state
        end

      _ ->
        state
    end
  end

  defp evict(state), do: state

  # Drop a single frame from the front of the buffer.
  defp drop_oldest_frame(state) do
    case :queue.out(state.buffer) do
      {:empty, _} ->
        %{state | keyframe_count: 0, buffer_size: 0}

      {{:value, buf}, rest} ->
        kf_adj = if Utils.keyframe(buf), do: -1, else: 0

        %{
          state
          | buffer: rest,
            buffer_size: state.buffer_size - payload_size(buf.payload),
            keyframe_count: state.keyframe_count + kf_adj
        }
    end
  end

  # Drop all frames from the front up to and including the oldest keyframe
  # (i.e. remove one coded video sequence).
  defp drop_oldest_cvs(state) do
    case :queue.out(state.buffer) do
      {:empty, _} ->
        %{state | keyframe_count: 0, buffer_size: 0}

      {{:value, buf}, rest} ->
        new_state = %{
          state
          | buffer: rest,
            buffer_size: state.buffer_size - payload_size(buf.payload),
            keyframe_count:
              if(Utils.keyframe(buf), do: state.keyframe_count - 1, else: state.keyframe_count)
        }

        if Utils.keyframe(buf) do
          new_state
        else
          drop_oldest_cvs(new_state)
        end
    end
  end

  defp log_buffer_span([]), do: :ok

  defp log_buffer_span(buffers) do
    first_pts = buffers |> List.first() |> buffer_pts()
    last_pts = buffers |> List.last() |> buffer_pts()

    if first_pts && last_pts do
      diff_ms = Membrane.Time.as_milliseconds(last_pts - first_pts, :round)

      Membrane.Logger.info(
        "Flushing buffer: #{length(buffers)} frames, " <>
          "first_pts=#{inspect(first_pts)}, last_pts=#{inspect(last_pts)}, " <>
          "span=#{diff_ms}ms"
      )
    else
      Membrane.Logger.info("Flushing buffer: #{length(buffers)} frames, pts unavailable")
    end
  end

  defp buffer_pts(%Membrane.Buffer{pts: pts}), do: pts

  defp payload_size(payload) when is_binary(payload), do: byte_size(payload)
  defp payload_size(payload) when is_list(payload), do: IO.iodata_length(payload)
end
