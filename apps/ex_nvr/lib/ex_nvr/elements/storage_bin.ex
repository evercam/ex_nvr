defmodule ExNVR.Elements.StorageBin do
  @moduledoc """
  Element responsible for splitting the stream into segments and save them as MP4 chunks
  """

  use Membrane.Bin

  require Membrane.Logger

  alias ExNVR.Elements.Segmenter.Segment
  alias ExNVR.Model.Run
  alias Membrane.H264

  def_input_pad :input,
    demand_mode: :auto,
    demand_unit: :buffers,
    accepted_format: %H264{alignment: :au},
    availability: :always

  def_options device_id: [
                spec: binary(),
                description: "The id of the device where this video belongs"
              ],
              target_segment_duration: [
                spec: non_neg_integer(),
                default: 60,
                description: """
                The duration of each segment in seconds.
                A segment may not have the exact duration specified here, since each
                segment must start from a keyframe. The real segment duration may be
                slightly bigger
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      bin_input(:input)
      |> child(:segmenter, %ExNVR.Elements.Segmenter{
        segment_duration: opts.target_segment_duration
      })
    ]

    state = %{
      device_id: opts.device_id,
      recordings_temp_dir: System.tmp_dir!(),
      pending_segments: %{},
      segment_extension: ".mp4",
      run: nil
    }

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:new_media_segment, segment_ref},
        :segmenter,
        _ctx,
        state
      ) do
    Membrane.Logger.info("start recording a new segment '#{segment_ref}'")

    spec = [
      get_child(:segmenter)
      |> via_out(Pad.ref(:output, segment_ref))
      |> child({:h264_mp4_payloader, segment_ref}, Membrane.MP4.Payloader.H264)
      |> child({:mp4_muxer, segment_ref}, %Membrane.MP4.Muxer.ISOM{fast_start: true})
      |> child({:sink, segment_ref}, %Membrane.File.Sink{
        location: Path.join(state.recordings_temp_dir, "#{segment_ref}.mp4")
      })
    ]

    {[spec: spec], state}
  end

  @impl true
  def handle_child_notification(
        {:completed_segment, {pad_ref, %Segment{} = segment, end_run?}},
        :segmenter,
        _ctx,
        state
      ) do
    segment = %Segment{
      segment
      | path: Path.join(state.recordings_temp_dir, "#{pad_ref}#{state.segment_extension}"),
        device_id: state.device_id
    }

    state = run_from_segment(state, segment, end_run?)

    {[], put_in(state, [:pending_segments, pad_ref], segment)}
  end

  # Once the sink receive end of stream and flush the segment to the filesystem
  # we can delete the childs
  @impl true
  def handle_element_end_of_stream({:sink, seg_ref}, _pad, _ctx, state) do
    children = [
      {:h264_mp4_payloader, seg_ref},
      {:mp4_muxer, seg_ref},
      {:sink, seg_ref}
    ]

    {state, segment} = do_save_recording(state, seg_ref)

    {[remove_child: children, notify_parent: {:segment_stored, segment}], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  defp do_save_recording(state, recording_ref) do
    {recording, state} = pop_in(state, [:pending_segments, recording_ref])

    case ExNVR.Recordings.create(state.run, recording) do
      {:ok, _, run} ->
        Membrane.Logger.info("segment saved successfully")
        File.rm(recording.path)
        {%{state | run: run}, recording}

      {:error, error} ->
        Membrane.Logger.error("""
        Could not save recording #{inspect(recording)}
        #{inspect(error)}
        """)

        {%{state | run: nil}, recording}
    end
  end

  defp run_from_segment(state, segment, end_run?) do
    if is_nil(state.run) do
      %{
        state
        | run: %Run{
            start_date: segment.start_date,
            end_date: segment.end_date,
            device_id: segment.device_id,
            active: not end_run?
          }
      }
    else
      %{state | run: %Run{state.run | end_date: segment.end_date, active: not end_run?}}
    end
  end
end
