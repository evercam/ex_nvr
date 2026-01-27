defmodule ExNVR.Pipeline.Output.Storage do
  @moduledoc false

  use Membrane.Sink

  require ExNVR.Utils
  require Membrane.Logger

  import ExNVR.MediaUtils

  alias ExMP4.{Box, Writer}
  alias ExNVR.Model.{Device, Run}
  alias ExNVR.Pipeline.Event.StreamClosed
  alias ExNVR.Pipeline.Output.Storage.Segment
  alias ExNVR.Utils
  alias Membrane.{Buffer, Event, H264, H265, Time}

  @time_error Time.milliseconds(30)
  @time_drift_threshold Time.seconds(30)

  @recordings_event [:ex_nvr, :recordings, :stop]

  def_input_pad :input,
    accepted_format:
      any_of(
        %H264{alignment: :au},
        %H265{alignment: :au}
      )

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
                spec: Time.t(),
                default: Time.seconds(60),
                description: """
                The duration of each segment.
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
              ],
              onvif_replay: [
                spec: boolean(),
                default: false
              ]

  @impl true
  def handle_init(_ctx, opts) do
    state =
      %{
        device: opts.device,
        stream: opts.stream,
        directory: Device.recording_dir(opts.device, opts.stream),
        target_duration: opts.target_segment_duration,
        correct_timestamp: opts.correct_timestamp,
        track: nil,
        onvif_replay: opts.onvif_replay
      }
      |> reset_state_fields()

    Process.set_label({:storage, opts.device.id, opts.stream})

    {[], state}
  end

  @impl true
  def handle_stream_format(:input, stream_format, ctx, state) do
    old_stream_format = ctx.pads[:input].stream_format

    cond do
      is_nil(old_stream_format) ->
        {[], %{state | track: track_from_stream_format(stream_format)}}

      same_stream_format?(old_stream_format, stream_format) ->
        {[], state}

      true ->
        state =
          state
          |> handle_discontinuity()
          |> Map.put(:track, track_from_stream_format(stream_format))

        {[], state}
    end
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{current_segment: nil} = state)
      when not Utils.keyframe(buffer) do
    {[], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{current_segment: nil} = state)
      when Utils.keyframe(buffer) do
    state =
      %{
        state
        | current_segment: Segment.new(Time.milliseconds(buffer.metadata.timestamp)),
          first_segment?: not state.onvif_replay,
          last_buffer: buffer,
          monotonic_start_time: System.monotonic_time()
      }
      |> open_file()

    {[notify_parent: :new_segment], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, %{current_segment: segment} = state) do
    state = write_data(state, buffer)

    if Utils.keyframe(buffer) and Segment.duration(segment) >= state.target_duration do
      {state, discontinuity} =
        finalize_segment(
          state,
          buffer.metadata.timestamp,
          state.correct_timestamp
        )

      state =
        state
        |> close_file(discontinuity)
        |> rename_first_segment(segment)

      # in case of time jump, we need to start a new segment
      start_time =
        if discontinuity,
          do: state.current_segment.wallclock_end_date,
          else: Segment.end_date(state.current_segment)

      state =
        %{
          state
          | current_segment: Segment.new(start_time),
            first_segment?: false,
            monotonic_start_time: System.monotonic_time()
        }
        |> open_file()

      {[notify_parent: :new_segment], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_event(:input, %Event.Discontinuity{}, _ctx, state) do
    {[], handle_discontinuity(state)}
  end

  @impl true
  def handle_event(:input, %StreamClosed{}, _ctx, state) do
    {[], handle_discontinuity(state)}
  end

  @impl true
  def handle_event(:input, _event, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[], handle_discontinuity(state)}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[terminate: :normal], handle_discontinuity(state)}
  end

  defp reset_state_fields(state) do
    Map.merge(state, %{
      run: nil,
      current_segment: nil,
      first_segment?: false,
      last_buffer: nil,
      writer: nil,
      monotonic_start_time: nil
    })
  end

  defp same_stream_format?(%module{} = sf1, %module{} = sf2) do
    Map.take(sf1, [:width, :height, :profile]) == Map.take(sf2, [:width, :height, :profile])
  end

  defp same_stream_format?(_, _), do: false

  defp handle_discontinuity(%{writer: nil} = state), do: state

  defp handle_discontinuity(state) do
    old_segment = state.current_segment
    {state, _discontinuity} = finalize_segment(state, DateTime.utc_now(), false)

    state
    |> close_file(true)
    |> rename_first_segment(old_segment)
    |> reset_state_fields()
  end

  defp finalize_segment(%{current_segment: segment} = state, end_date, correct_timestamp) do
    end_date = Time.milliseconds(end_date)
    monotonic_duration = Time.monotonic_time() - state.monotonic_start_time

    {segment, discontinuity?} =
      maybe_correct_timestamp(segment, correct_timestamp, state, end_date)

    segment =
      segment
      |> Segment.with_realtime_duration(monotonic_duration)
      |> Segment.with_wall_clock_duration(end_date - segment.start_date)
      |> then(&%{&1 | wallclock_end_date: end_date})

    {%{state | current_segment: segment}, discontinuity?}
  end

  defp maybe_correct_timestamp(segment, false, %{first_segment?: false}, _end_date),
    do: {segment, false}

  defp maybe_correct_timestamp(segment, true, %{first_segment?: false}, end_date) do
    # clap the time diff between -@time_error and @time_error
    time_diff = end_date - Segment.end_date(segment)

    if abs(time_diff) >= @time_drift_threshold do
      Membrane.Logger.warning("""
      Diff between segment end date and current date is more than #{Time.as_seconds(@time_drift_threshold, :round)} seconds
      diff: #{Time.as_microseconds(time_diff, :round)}
      """)

      {segment, true}
    else
      diff = time_diff |> max(-@time_error) |> min(@time_error)
      {Segment.add_duration(segment, diff), false}
    end
  end

  defp maybe_correct_timestamp(segment, _correct_timestamp, _state, end_date) do
    start_date = end_date - Segment.duration(segment)
    {%{segment | start_date: start_date, end_date: end_date}, false}
  end

  defp open_file(%{current_segment: segment} = state) do
    Membrane.Logger.info("Start recording a new segment")

    start_date = Segment.start_date(segment)
    recording_path = recording_path(state, start_date)
    File.mkdir_p!(Path.dirname(recording_path))

    writer =
      Writer.new!(recording_path, fast_start: true)
      |> Writer.write_header()
      |> Writer.add_track(state.track)

    %{state | writer: writer, track: Writer.tracks(writer) |> List.first()}
  end

  defp write_data(%{track: track} = state, buffer) do
    last_buffer = state.last_buffer
    timescale = state.track.timescale
    duration = Buffer.get_dts_or_pts(buffer) - Buffer.get_dts_or_pts(last_buffer)

    key_frame? = Utils.keyframe(last_buffer)

    {state, au} =
      cond do
        not key_frame? ->
          {state, last_buffer.payload}

        track.media == :h264 ->
          {{sps, pps}, au} = MediaCodecs.H264.pop_parameter_sets(last_buffer.payload)
          state = %{state | track: %{state.track | priv_data: Box.Avcc.new(sps, pps)}}
          {state, au}

        track.media == :h265 ->
          {{vps, sps, pps}, au} = MediaCodecs.H265.pop_parameter_sets(last_buffer.payload)
          state = %{state | track: %{state.track | priv_data: Box.Hvcc.new(vps, sps, pps)}}
          {state, au}
      end

    writer =
      Writer.write_sample(state.writer, %ExMP4.Sample{
        track_id: state.track.id,
        dts: ExMP4.Helper.timescalify(Buffer.get_dts_or_pts(last_buffer), :nanosecond, timescale),
        pts: ExMP4.Helper.timescalify(last_buffer.pts, :nanosecond, timescale),
        sync?: key_frame?,
        payload: MediaCodecs.H264.annexb_to_elementary_stream(au),
        duration: ExMP4.Helper.timescalify(duration, :nanosecond, timescale)
      })

    segment =
      state.current_segment
      |> Segment.add_duration(duration)
      |> Segment.add_size(IO.iodata_length(last_buffer.payload))

    %{
      state
      | last_buffer: buffer,
        writer: writer,
        current_segment: segment
    }
  end

  defp close_file(state, discontinuity?) do
    %{writer: writer, track: track, current_segment: segment} = state

    :ok =
      writer
      |> Writer.update_track(track.id, priv_data: track.priv_data)
      |> Writer.write_trailer()

    state = %{run_from_segment(state, segment, discontinuity?) | writer: nil}

    recording = %{
      start_date: Segment.start_date(segment) |> Time.to_datetime(),
      end_date: Segment.end_date(segment) |> Time.to_datetime(),
      path: recording_path(state, Segment.start_date(segment)),
      stream: state.stream,
      device_id: state.device.id
    }

    case ExNVR.Recordings.create(state.device, state.run, recording, false) do
      {:ok, _, run} ->
        duration_ms = Time.as_milliseconds(Segment.duration(segment), :round)

        log_recording_details(state, segment)

        :telemetry.execute(
          @recordings_event,
          %{duration: duration_ms, size: Segment.size(segment)},
          %{device_id: state.device.id, stream: state.stream}
        )

        unless run.active do
          Membrane.Logger.info("run discontinuity: #{run.id}")
        end

        maybe_new_run(state, run)

      {:error, error} ->
        Membrane.Logger.error("""
        Could not save recording #{inspect(recording)}
        #{inspect(error)}
        """)

        maybe_new_run(state, nil)
    end
  end

  defp recording_path(state, start_date) do
    start_date = div(start_date, 1_000)
    date = DateTime.from_unix!(start_date, :microsecond)

    [state.directory | ExNVR.Utils.date_components(date)]
    |> Path.join()
    |> Path.join("#{start_date}.mp4")
  end

  defp run_from_segment(%{run: nil} = state, segment, end_run?) do
    run = %Run{
      start_date: Segment.start_date(segment) |> Time.to_datetime(),
      end_date: Segment.end_date(segment) |> Time.to_datetime(),
      device_id: state.device.id,
      stream: state.stream,
      active: not end_run?,
      disk_serial: get_disk_serial(state.device.storage_config.address)
    }

    %{state | run: run}
  end

  defp run_from_segment(state, segment, end_run?) do
    run = %{
      state.run
      | end_date: Membrane.Time.to_datetime(segment.end_date),
        active: not end_run?
    }

    %{state | run: run}
  end

  defp maybe_new_run(state, %Run{active: true} = run), do: %{state | run: run}
  defp maybe_new_run(state, _run), do: %{state | run: nil}

  defp rename_first_segment(%{first_segment?: true} = state, segment) do
    # first segment has its start date adjusted
    # because of camera buffering

    dest = recording_path(state, Segment.start_date(state.current_segment))
    File.mkdir_p!(Path.dirname(dest))
    File.rename!(recording_path(state, Segment.start_date(segment)), dest)

    state
  end

  defp rename_first_segment(state, _segment), do: state

  defp log_recording_details(%{onvif_replay: true} = state, segment) do
    duration_ms = Time.as_milliseconds(Segment.duration(segment), :round)

    Membrane.Logger.info("""
    Replay segment saved successfully
      Stream: #{state.stream}
      Media duration: #{duration_ms} ms
      Size: #{div(Segment.size(segment), 1024)} KiB
      Segment end date: #{Segment.end_date(segment) |> Time.to_datetime()}
    """)
  end

  defp log_recording_details(state, segment) do
    duration_ms = Time.as_milliseconds(Segment.duration(segment), :round)

    Membrane.Logger.info("""
    Segment saved successfully
      Stream: #{state.stream}
      Media duration: #{duration_ms} ms
      Realtime (monotonic) duration: #{Time.as_milliseconds(Segment.realtime_duration(segment), :round)} ms
      Wallclock duration: #{Time.as_milliseconds(Segment.wall_clock_duration(segment), :round)} ms
      Size: #{div(Segment.size(segment), 1024)} KiB
      Segment end date: #{Segment.end_date(segment) |> Time.to_datetime()}
      Current date time: #{Time.to_datetime(segment.wallclock_end_date)}
    """)
  end

  defp get_disk_serial(mountpoint) do
    case ExNVR.Disk.list_drives() do
      {:ok, drives} ->
        drives
        |> Enum.find(%{serial: nil}, &ExNVR.Disk.has_mountpoint?(&1, mountpoint))
        |> Map.get(:serial)

      _error ->
        nil
    end
  end
end
