defmodule ExNVR.Elements.Segmenter do
  @moduledoc """
  Element responsible for splitting the stream into segments of fixed duration.

  Once the duration of a segment reach the `segment_duration` specified, a new notification is
  sent to the parent to inform it of the start of a new segment.

  The parent should link the `Pad.ref(:output, segment_ref)` to start receiving the data of the new segment.

  Note that an `end_of_stream` action is sent on the old `Pad.ref(:output, segment_ref)`
  """

  use Membrane.Filter

  require Membrane.Logger

  alias ExNVR.Elements.Segmenter.Segment
  alias Membrane.{Buffer, Event, H264}

  def_options segment_duration: [
                spec: non_neg_integer(),
                default: 60,
                description: """
                The duration of each segment in seconds.
                A segment may not have the exact duration specified here, since each
                segment must start from a keyframe. The real segment duration may be
                slightly bigger
                """
              ],
              sps: [
                spec: binary(),
                default: <<>>,
                description: """
                Sequence Parameter Set, if not set, maybe provided in the bitstream.

                sps will be appended to the first keyframe of each segment
                """
              ],
              pps: [
                spec: binary(),
                default: <<>>,
                description: """
                Picture Parameter Set, if not set, maybe provided in the bitstream.

                pps will be appended to the first keyframe of each segment
                """
              ]

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :always

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: %H264{alignment: :au},
    availability: :on_request

  @impl true
  def handle_init(_ctx, options) do
    state =
      Map.merge(init_state(), %{
        stream_format: nil,
        target_segment_duration: Membrane.Time.seconds(options.segment_duration),
        sps: options.sps,
        pps: options.pps
      })

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[], %{state | stream_format: stream_format}}
  end

  @impl true
  def handle_pad_added(Pad.ref(:output, ref), _ctx, %{start_time: ref} = state) do
    buffered_actions =
      state.buffer
      |> Enum.reverse()
      |> Enum.map(&{:buffer, {Pad.ref(:output, ref), &1}})

    {[stream_format: {Pad.ref(:output, ref), state.stream_format}] ++ buffered_actions,
     %{state | buffer?: false, buffer: []}}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{metadata: %{h264: %{key_frame?: false}}},
        _ctx,
        %{start_time: nil} = state
      ) do
    # ignore, we need to start recording from a keyframe
    {[], state}
  end

  @impl true
  def handle_process(
        :input,
        %Buffer{metadata: %{h264: %{key_frame?: true}}} = buf,
        _ctx,
        %{start_time: nil} = state
      ) do
    # we chose the os_time instead of vm_time since the
    # VM will not adjust the time when the the system is suspended
    # check https://erlangforums.com/t/why-is-there-a-discrepancy-between-values-returned-by-os-system-time-1-and-erlang-system-time-1/2050/2
    state = %{
      state
      | start_time: Membrane.Time.os_time(),
        buffer: [prepend_sps_and_pps(state, buf)],
        last_buffer_pts: buf.pts
    }

    {[notify_parent: {:new_media_segment, state.start_time}], state}
  end

  @impl true
  def handle_process(:input, %Buffer{} = buf, _ctx, state) do
    state
    |> update_segment_duration(buf)
    |> handle_buffer(buf)
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    do_handle_end_of_stream(state)
  end

  @impl true
  def handle_event(:input, %Event.Discontinuity{}, _ctx, state) do
    do_handle_end_of_stream(state)
  end

  defp handle_buffer(%{buffer?: true} = state, buffer) do
    {[], %{state | buffer: [buffer | state.buffer]}}
  end

  defp handle_buffer(state, %Buffer{metadata: %{h264: %{key_frame?: true}}} = buffer)
       when state.current_segment_duration >= state.target_segment_duration do
    completed_segment_action = completed_segment_action(state)
    pad_ref = state.start_time

    state = %{
      state
      | start_time: state.start_time + state.current_segment_duration,
        current_segment_duration: 0,
        buffer?: true,
        buffer: [prepend_sps_and_pps(state, buffer)]
    }

    {[
       end_of_stream: Pad.ref(:output, pad_ref),
       notify_parent: {:new_media_segment, state.start_time}
     ] ++ completed_segment_action, state}
  end

  defp handle_buffer(state, buffer),
    do: {[buffer: {Pad.ref(:output, state.start_time), buffer}], state}

  defp do_handle_end_of_stream(%{start_time: nil} = state) do
    {[], state}
  end

  defp do_handle_end_of_stream(state) do
    {[end_of_stream: Pad.ref(:output, state.start_time)] ++ completed_segment_action(state, true),
     Map.merge(state, init_state())}
  end

  defp update_segment_duration(state, %Buffer{pts: pts} = buf) do
    frame_duration = pts - state.last_buffer_pts

    %{
      state
      | current_segment_duration: state.current_segment_duration + frame_duration,
        last_buffer_pts: buf.pts
    }
  end

  defp init_state() do
    %{
      current_segment_duration: 0,
      last_buffer_pts: nil,
      buffer: [],
      buffer?: true,
      start_time: nil,
      parameter_sets: []
    }
  end

  defp completed_segment_action(state, discontinuity \\ false) do
    segment = Segment.new(state.start_time, state.current_segment_duration)
    [notify_parent: {:completed_segment, {state.start_time, segment, discontinuity}}]
  end

  # Prepend SPS and PPS is useful in case this parameter sets
  # are not sent frequently on the bytestream.
  # The MP4 payloader needs this parameters sets
  # This needs to be done by the Parser.
  defp prepend_sps_and_pps(%{sps: <<>>, pps: <<>>}, %Buffer{} = access_unit), do: access_unit

  defp prepend_sps_and_pps(%{sps: sps, pps: pps}, %Buffer{} = access_unit) do
    nalus_type = Enum.map(access_unit.metadata.h264.nalus, & &1.metadata.h264.type)
    has_parameter_sets? = :sps in nalus_type and :pps in nalus_type

    if has_parameter_sets?, do: access_unit, else: do_prepend_sps_and_pps(access_unit, sps, pps)
  end

  defp do_prepend_sps_and_pps(access_unit, sps, pps) do
    sps = maybe_add_prefix(sps)
    pps = maybe_add_prefix(pps)

    parameter_set_nalus =
      Enum.map([{:sps, sps}, {:pps, pps}], fn {type, parameter_set} ->
        %{type: type, payload: parameter_set, prefix_length: 4}
      end)

    parameter_set_total_length = byte_size(sps) + byte_size(pps)

    access_unit_nalus =
      Enum.map(access_unit.metadata.h264.nalus, fn nalu_metadata ->
        {_, nalu_metadata} = pop_in(nalu_metadata, [:metadata, :h264, :new_access_unit])

        nalu_metadata
        |> Map.update!(:prefixed_poslen, fn {start, length} ->
          {parameter_set_total_length + start, length}
        end)
        |> Map.update!(:unprefixed_poslen, fn {start, length} ->
          {parameter_set_total_length + start, length}
        end)
      end)

    parameter_set_nalus =
      parameter_set_nalus
      |> Enum.with_index()
      |> Enum.map_reduce(0, fn {nalu, i}, nalu_start ->
        metadata = %{
          metadata: %{
            h264: %{
              type: nalu.type
            }
          },
          prefixed_poslen: {nalu_start, byte_size(nalu.payload)},
          unprefixed_poslen:
            {nalu_start + nalu.prefix_length, byte_size(nalu.payload) - nalu.prefix_length}
        }

        metadata =
          if i == 0 do
            put_in(metadata, [:metadata, :h264, :new_access_unit], %{key_frame?: true})
          else
            metadata
          end

        {metadata, nalu_start + byte_size(nalu.payload)}
      end)
      |> elem(0)

    %Buffer{
      access_unit
      | payload: sps <> pps <> access_unit.payload,
        metadata:
          put_in(access_unit.metadata, [:h264, :nalus], parameter_set_nalus ++ access_unit_nalus)
    }
  end

  defp maybe_add_prefix(parameter_set) do
    case parameter_set do
      <<>> -> <<>>
      <<0, 0, 1, _rest::binary>> -> parameter_set
      <<0, 0, 0, 1, _rest::binary>> -> parameter_set
      parameter_set -> <<0, 0, 0, 1>> <> parameter_set
    end
  end
end
