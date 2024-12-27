defmodule ExNVR.Elements.Recording do
  @moduledoc """
  An element that streams samples from the recordings chunks as if it is
  one big file.
  """

  use Membrane.Source

  require Membrane.Logger

  alias ExMP4.{Helper, Reader}
  alias ExNVR.Model.Device
  alias ExNVR.Pipeline
  alias ExNVR.Recordings

  @timescale :nanosecond

  def_options device: [
                spec: Device.t(),
                description: "The device from where to read the recordings"
              ],
              stream: [
                spec: :high | :low,
                default: :high,
                description: "The stream type"
              ],
              start_date: [
                spec: DateTime.t(),
                description: "The start date of the recording"
              ],
              end_date: [
                spec: DateTime.t(),
                default: ~U(2099-01-01 00:00:00Z),
                description: """
                The end date of the recording.

                Note that if both `duration` and `end_date` are provided, an
                `end_of_stream` will be sent on the first satisfied condition.
                """
              ],
              duration: [
                spec: Membrane.Time.t(),
                default: 0,
                description: """
                The total duration of the stream before sending `end_of_stream`.

                Note that if both `duration` and `end_date` are provided, an
                `end_of_stream` will be sent on the first satisfied condition.
                """
              ]

  def_output_pad :video,
    accepted_format:
      any_of(
        %Membrane.H264{alignment: :au},
        %Membrane.H265{alignment: :au}
      ),
    availability: :on_request,
    flow_control: :manual

  defmodule State do
    @moduledoc false

    defstruct device: nil,
              stream: :high,
              start_date: nil,
              end_date: nil,
              duration: nil,
              recordings: [],
              current_recording: nil,
              reader: nil,
              tracks: %{}
  end

  @impl true
  def handle_init(_ctx, options) do
    state = %State{
      device: options.device,
      stream: options.stream,
      start_date: options.start_date,
      end_date: options.end_date,
      duration: options.duration
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    case open_next_file(state) do
      {:eos, state} ->
        {[], state}

      state ->
        actions =
          Enum.map(state.tracks, fn {_type, track_details} ->
            {:notify_parent,
             {:new_track, track_details.track.id, Pipeline.Track.new(track_details.track)}}
          end)

        {actions, state}
    end
  end

  @impl true
  def handle_pad_added(Pad.ref(:video, id) = pad, _ctx, state) do
    %{track: track} =
      Reader.track(state.reader, id)
      |> Map.get(:type)
      |> then(&Map.fetch!(state.tracks, &1))

    stream_format =
      case track.media do
        :h264 -> %Membrane.H264{alignment: :au, width: track.width, height: track.height}
        :h265 -> %Membrane.H265{alignment: :au, width: track.width, height: track.height}
      end

    {[stream_format: {pad, stream_format}], state}
  end

  @impl true
  def handle_demand(Pad.ref(:video, id) = pad, demand, :buffers, _ctx, state) do
    type = Reader.track(state.reader, id) |> Map.get(:type)
    demand = min(demand, 30)

    {buffers, track_details} =
      Enum.reduce_while(1..demand, {[], state.tracks[type]}, fn _idx, {buffers, track_details} ->
        with {:ok, {sample, timestamp, track_details}} <- read_next_sample(state, track_details),
             buffer <- map_sample_to_buffer(sample, track_details.track),
             :ok <- check_duration_and_end_date(state, buffer, timestamp) do
          {:cont, {[buffer | buffers], track_details}}
        else
          :eos -> {:halt, {buffers, track_details}}
          {:end_of_file, track_details} -> {:halt, {buffers, track_details}}
        end
      end)

    state = %State{state | tracks: Map.put(state.tracks, type, track_details)}
    buffers = Enum.reverse(buffers)

    cond do
      track_details.state == :end_of_file ->
        # In case we add support for audio tracks
        # we need first to check that all tracks finished
        # reading before opening next file
        case open_next_file(state) do
          {:eos, state} -> {[buffer: {pad, buffers}, end_of_stream: pad], state}
          state -> {[buffer: {pad, buffers}, redemand: pad], state}
        end

      length(buffers) == demand ->
        {[buffer: {pad, buffers}, redemand: pad], state}

      true ->
        {[buffer: {pad, buffers}, end_of_stream: pad], state}
    end
  end

  defp open_next_file(%State{recordings: []} = state) do
    start_date =
      if state.current_recording,
        do: state.current_recording.end_date,
        else: state.start_date

    recordings =
      Recordings.get_recordings_between(
        state.device.id,
        state.stream,
        start_date,
        state.end_date
      )

    case recordings do
      [] -> {:eos, state}
      _ -> %State{state | recordings: recordings} |> open_next_file()
    end
  end

  defp open_next_file(%State{recordings: [recording | recordings]} = state) do
    reader = Recordings.recording_path(state.device, state.stream, recording) |> Reader.new!()

    tracks =
      Reader.tracks(reader)
      |> Enum.filter(&(&1.type == :video))
      |> Map.new(fn track ->
        {:ok, bit_stream_filter} = ExMP4.BitStreamFilter.MP4ToAnnexb.init(track, [])
        {reducer, offset} = maybe_seek(reader, track, recording.start_date, state.start_date)

        track_duration =
          DateTime.diff(recording.end_date, recording.start_date, :microsecond)
          |> Helper.timescalify(:microsecond, track.timescale)

        {old_duration, old_offset} =
          case state.tracks[track.type] do
            nil -> {0, -offset}
            old_track -> {old_track.track_duration, old_track.offset}
          end

        track_details = %{
          track: track,
          track_duration: track_duration,
          reducer: reducer,
          bit_stream_filter: bit_stream_filter,
          state: :reading,
          offset: old_offset + old_duration
        }

        {track.type, track_details}
      end)

    # TODO: compare with current track for potential codec changes

    %State{
      state
      | reader: reader,
        recordings: recordings,
        tracks: tracks,
        current_recording: recording
    }
  end

  defp maybe_seek(reader, track, recording_start_date, start_date) do
    reducer = &Enumerable.reduce(track, &1, fn elem, _acc -> {:suspend, elem} end)

    case DateTime.compare(recording_start_date, start_date) do
      :lt ->
        offset =
          start_date
          |> DateTime.diff(recording_start_date, :millisecond)
          |> Helper.timescalify(:millisecond, track.timescale)

        keyframe_dts =
          reader
          |> Reader.stream(tracks: [track.id])
          |> Enum.reduce_while(0, fn metadata, acc ->
            cond do
              metadata.sync? -> {:cont, metadata.dts}
              metadata.dts >= offset -> {:halt, acc}
              true -> {:cont, acc}
            end
          end)

        {read_until(reducer, keyframe_dts), keyframe_dts}

      _other ->
        {reducer, 0}
    end
  end

  defp read_until(reducer, dts) do
    {:suspended, sample_metadata, new_reducer} = reducer.({:cont, nil})

    if sample_metadata.dts == dts do
      reducer
    else
      read_until(new_reducer, dts)
    end
  end

  defp read_next_sample(%State{} = state, track_details) do
    %{reducer: reducer, bit_stream_filter: filter} = track_details
    %{reader: reader, current_recording: recording} = state

    case reducer.({:cont, nil}) do
      {:suspended, sample_metadata, new_reducer} ->
        {sample, _bit_stream_filter} =
          reader
          |> Reader.read_sample(sample_metadata)
          |> then(&ExMP4.BitStreamFilter.MP4ToAnnexb.filter(filter, &1))

        dts_in_ms = Helper.timescalify(sample.dts, track_details.track.timescale, :millisecond)
        sample_timestamp = DateTime.add(recording.start_date, dts_in_ms, :millisecond)

        sample = %{
          sample
          | dts: sample.dts + track_details.offset,
            pts: sample.pts + track_details.offset
        }

        {:ok, {sample, sample_timestamp, %{track_details | reducer: new_reducer}}}

      {:done, nil} ->
        {:end_of_file, %{track_details | state: :end_of_file}}
    end
  end

  defp check_duration_and_end_date(%State{} = state, buffer, sample_timestamp) do
    cond do
      state.duration != 0 and buffer.dts > state.duration ->
        :eos

      DateTime.compare(sample_timestamp, state.end_date) != :lt ->
        :eos

      true ->
        :ok
    end
  end

  defp map_sample_to_buffer(sample, track) do
    %Membrane.Buffer{
      payload: sample.payload,
      dts: Helper.timescalify(sample.dts, track.timescale, @timescale),
      pts: Helper.timescalify(sample.pts, track.timescale, @timescale)
    }
  end
end
