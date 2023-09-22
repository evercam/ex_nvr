defmodule ExNVR.Pipeline.Output.Storage do
  @moduledoc """
  Split the incoming streams into segments/chunks and save them on disk
  """

  use Membrane.Bin

  require Membrane.Logger

  alias __MODULE__.{Segmenter, Segmenter.Segment}
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
              directory: [
                spec: Path.t(),
                description: "The directory where to store the video segments"
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
      |> child(:segmenter, %Segmenter{
        target_duration: opts.target_segment_duration
      })
    ]

    state = %{
      device_id: opts.device_id,
      directory: opts.directory,
      pending_segments: %{},
      segment_extension: ".mp4",
      run: nil,
      terminating?: false,
      end_of_stream?: false
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
        location: recording_path(state, segment_ref)
      })
    ]

    {[spec: {spec, group: segment_ref}], state}
  end

  @impl true
  def handle_child_notification(
        {:completed_segment, {pad_ref, %Segment{} = segment, end_run?}},
        :segmenter,
        _ctx,
        state
      ) do
    state = run_from_segment(state, segment, end_run?)
    {[], put_in(state, [:pending_segments, pad_ref], segment)}
  end

  # Once the sink receive end of stream and flush the segment to the filesystem
  # we can delete the childs
  @impl true
  def handle_element_end_of_stream({:sink, seg_ref}, _pad, _ctx, state) do
    {state, segment} = do_save_recording(state, seg_ref)

    actions = [remove_child: seg_ref, notify_parent: {:segment_stored, segment}]
    terminate_action = if state.terminating?, do: [terminate: :normal], else: []

    {actions ++ terminate_action, state}
  end

  @impl true
  def handle_element_end_of_stream(:segmenter, _pad, _ctx, state) do
    {[], %{state | end_of_stream?: true}}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    if state.end_of_stream? do
      {[terminate: :normal], state}
    else
      {[], %{state | terminating?: true}}
    end
  end

  defp do_save_recording(state, recording_ref) do
    {segment, state} = pop_in(state, [:pending_segments, recording_ref])

    recording = %{
      start_date: Membrane.Time.to_datetime(segment.start_date),
      end_date: Membrane.Time.to_datetime(segment.end_date),
      path: recording_path(state, segment.start_date),
      device_id: state.device_id
    }

    # first segment has its start date adjusted
    if is_nil(state.run.id) do
      File.rename!(
        recording_path(state, recording_ref),
        recording_path(state, segment.start_date)
      )
    end

    case ExNVR.Recordings.create(state.run, recording, false) do
      {:ok, _, run} ->
        Membrane.Logger.info("""
        Segment saved successfully
          Media duration: #{Membrane.Time.round_to_milliseconds(Segment.duration(segment))} ms
          Realtime (monotonic) duration: #{Membrane.Time.round_to_milliseconds(Segment.realtime_duration(segment))} ms
          Wallclock duration: #{Membrane.Time.round_to_milliseconds(Segment.wall_clock_duration(segment))} ms
          Size: #{div(Segment.size(segment), 1024)} KiB
          Segment end date: #{recording.end_date}
          Current date time: #{Membrane.Time.to_datetime(segment.wallclock_end_date)}
        """)

        {maybe_new_run(state, run), recording}

      {:error, error} ->
        Membrane.Logger.error("""
        Could not save recording #{inspect(recording)}
        #{inspect(error)}
        """)

        {maybe_new_run(state, nil), recording}
    end
  end

  defp run_from_segment(%{run: nil} = state, segment, end_run?) do
    run = %Run{
      start_date: Membrane.Time.to_datetime(segment.start_date),
      end_date: Membrane.Time.to_datetime(segment.end_date),
      device_id: state.device_id,
      active: !end_run?
    }

    %{state | run: run}
  end

  defp run_from_segment(state, segment, end_run?) do
    %{
      state
      | run: %Run{
          state.run
          | end_date: Membrane.Time.to_datetime(segment.end_date),
            active: not end_run?
        }
    }
  end

  defp maybe_new_run(state, %Run{active: true} = run), do: %{state | run: run}
  defp maybe_new_run(state, _run), do: %{state | run: nil}

  defp recording_path(state, start_date) do
    Path.join(state.directory, "#{div(start_date, 1_000)}#{state.segment_extension}")
  end
end
