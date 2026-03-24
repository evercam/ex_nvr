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
      stream_format: nil
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
    {[buffer: {:output, buffer}], state}
  end

  # --- Buffering mode: accumulate frames ---
  @impl true
  def handle_buffer(:input, buffer, _ctx, %{mode: :buffering} = state) do
    is_keyframe = Utils.keyframe(buffer)

    keyframe_count =
      if is_keyframe, do: state.keyframe_count + 1, else: state.keyframe_count

    queue = :queue.in(buffer, state.buffer)
    buffer_size = state.buffer_size + payload_size(buffer.payload)

    state = %{
      state
      | buffer: queue,
        buffer_size: buffer_size,
        keyframe_count: keyframe_count
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

  # Drop all frames belonging to the oldest coded video sequence:
  # the leading keyframe and every non-keyframe that follows it,
  # stopping just before the next keyframe.
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

        # If we just dropped a non-keyframe, keep dropping (looking for the keyframe).
        # If we dropped a keyframe, continue dropping trailing non-keyframes.
        case :queue.peek(new_state.buffer) do
          {:value, next_buf} ->
            if Utils.keyframe(next_buf) do
              # Next frame starts a new CVS — stop here
              new_state
            else
              # Still in the same CVS (or leading orphans) — keep dropping
              drop_oldest_cvs(new_state)
            end

          :empty ->
            new_state
        end
    end
  end

  defp buffer_pts(%Membrane.Buffer{pts: pts}), do: pts

  defp payload_size(payload) when is_binary(payload), do: byte_size(payload)
  defp payload_size(payload) when is_list(payload), do: IO.iodata_length(payload)
end
