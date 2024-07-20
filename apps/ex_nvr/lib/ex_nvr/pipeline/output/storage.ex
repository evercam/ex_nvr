defmodule ExNVR.Pipeline.Output.Storage do
  @moduledoc """
  Split the incoming streams into segments/chunks and save them on disk
  """

  use Membrane.Bin

  require Membrane.Logger

  alias __MODULE__.{Segmenter, Segmenter.Segment}
  alias ExNVR.Model.{Device, Run}
  alias Membrane.{H264, H265}

  @recordings_event [:ex_nvr, :recordings, :stop]
  @interval Membrane.Time.seconds(5)

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      ),
    availability: :always

  def_options device: [
                spec: Device.t(),
                description: "The device where this video belongs"
              ],
              stream: [
                spec: :high | :low,
                default: :high,
                description: """
                The type of the stream to store.
                  * `high` - main stream
                  * `low` - sub stream
                """
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
              ],
              correct_timestamp: [
                spec: boolean(),
                default: false,
                description: """
                Segment duration are calculated from the frame duration usin RTP timestamps.

                Camera clocks are not accurate, in a long run it'll drift from the NVR time.
                Setting this to `true` will correct the segment end date towards the wall clock of the server.

                The max error the date will be adjusted is in the range ± 30 ms.
                """
              ]

  @impl true
  def handle_init(_ctx, opts) do
    spec = [
      bin_input(:input)
      |> child(:tee, Membrane.Tee.Parallel)
    ]

    dest = Device.recording_dir(opts.device, opts.stream)

    state = %{
      device: opts.device,
      stream: opts.stream,
      directory: dest,
      pending_segments: %{},
      segment_extension: ".mp4",
      run: nil,
      terminating?: false,
      end_of_stream?: false,
      target_duration: opts.target_segment_duration,
      correct_timestamp: opts.correct_timestamp
    }

    actions =
      case ExNVR.Utils.writable(dest) do
        :ok ->
          [spec: spec ++ [get_child(:tee) |> segmenter_spec(state)]]

        {:error, reason} ->
          Membrane.Logger.error(
            "Destination '#{dest}' is not writable, error: #{inspect(reason)}"
          )

          [spec: spec, start_timer: {:recording_dir, @interval}]
      end

    {actions, state}
  end

  @impl true
  def handle_child_notification(
        {:new_media_segment, segment_ref, codec},
        :segmenter,
        _ctx,
        state
      ) do
    Membrane.Logger.info("start recording a new segment '#{segment_ref}'")

    recording_path = recording_path(state, segment_ref)
    File.mkdir_p!(Path.dirname(recording_path))

    spec = [
      get_child(:segmenter)
      |> via_out(Pad.ref(:output, segment_ref))
      |> child({:mp4_payloader, segment_ref}, get_parser(codec))
      |> child({:mp4_muxer, segment_ref}, %Membrane.MP4.Muxer.ISOM{fast_start: true})
      |> child({:sink, segment_ref}, %Membrane.File.Sink{
        location: recording_path
      })
    ]

    {[spec: {spec, group: segment_ref, crash_group_mode: :temporary}], state}
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

    actions = [remove_children: seg_ref, notify_parent: {:segment_stored, state.stream, segment}]
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
  def handle_tick(:recording_dir, _ctx, state) do
    case ExNVR.Utils.writable(state.directory) do
      :ok ->
        Membrane.Logger.info("Destination '#{state.directory}' is writable")
        {[spec: [get_child(:tee) |> segmenter_spec(state)], stop_timer: :recording_dir], state}

      _error ->
        {[], state}
    end
  end

  @impl true
  def handle_crash_group_down(group_name, _ctx, state) do
    Membrane.Logger.error("crash in storage bin: #{group_name}")

    {[
       start_timer: {:recording_dir, @interval},
       remove_children: [:segmenter]
     ], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    if state.end_of_stream? do
      {[terminate: :normal], state}
    else
      {[], %{state | terminating?: true}}
    end
  end

  defp segmenter_spec(link_builder, state) do
    child(link_builder, :segmenter, %Segmenter{
      target_duration: state.target_duration,
      correct_timestamp: state.correct_timestamp
    })
  end

  defp get_parser(:H264), do: %Membrane.H264.Parser{output_stream_structure: :avc1}
  defp get_parser(:H265), do: %Membrane.H265.Parser{output_stream_structure: :hvc1}

  defp do_save_recording(state, recording_ref) do
    {segment, state} = pop_in(state, [:pending_segments, recording_ref])

    recording = %{
      start_date: Membrane.Time.to_datetime(segment.start_date),
      end_date: Membrane.Time.to_datetime(segment.end_date),
      path: recording_path(state, segment.start_date),
      stream: state.stream,
      device_id: state.device.id
    }

    # first segment has its start date adjusted
    if is_nil(state.run.id) do
      File.rename!(
        recording_path(state, recording_ref),
        recording_path(state, segment.start_date)
      )
    end

    case ExNVR.Recordings.create(state.device, state.run, recording, false) do
      {:ok, _, run} ->
        duration_ms = Membrane.Time.as_milliseconds(Segment.duration(segment), :round)

        Membrane.Logger.info("""
        Segment saved successfully
          Stream: #{state.stream}
          Media duration: #{duration_ms} ms
          Realtime (monotonic) duration: #{Membrane.Time.as_milliseconds(Segment.realtime_duration(segment), :round)} ms
          Wallclock duration: #{Membrane.Time.as_milliseconds(Segment.wall_clock_duration(segment), :round)} ms
          Size: #{div(Segment.size(segment), 1024)} KiB
          Segment end date: #{recording.end_date}
          Current date time: #{Membrane.Time.to_datetime(segment.wallclock_end_date)}
        """)

        :telemetry.execute(
          @recordings_event,
          %{duration: duration_ms, size: Segment.size(segment)},
          %{device_id: state.device.id, stream: state.stream}
        )

        unless run.active do
          Membrane.Logger.info("run discontinuity: #{run.id}")
        end

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
      device_id: state.device.id,
      stream: state.stream,
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
    start_date = div(start_date, 1_000)
    date = DateTime.from_unix!(start_date, :microsecond)

    Path.join(
      [state.directory | ExNVR.Utils.date_components(date)] ++
        ["#{start_date}#{state.segment_extension}"]
    )
  end
end
