defmodule ExNVR.Recordings.Concatenater do
  @moduledoc """
  Read samples from all the recordings chunks as if it is one big file.
  """

  import ExMP4.Helper, only: [timescalify: 3]

  alias ExMP4.{BitStreamFilter, Reader, Track}
  alias ExNVR.Model.Device
  alias ExNVR.Recordings

  @default_end_date ~U(2999-01-01 00:00:00Z)
  @video_timescale 90_000

  @opaque t :: %__MODULE__{
            device: Device.t(),
            stream: Recordings.stream_type(),
            start_date: DateTime.t(),
            recordings: [ExNVR.Model.Recording.t()],
            current_recording: ExNVR.Model.Recording.t() | nil,
            reader: Reader.t() | nil,
            tracks: map()
          }

  defstruct device: nil,
            stream: :high,
            start_date: nil,
            recordings: [],
            current_recording: nil,
            reader: nil,
            tracks: %{},
            annexb?: true

  @spec new(Device.t(), Recordings.stream_type(), DateTime.t(), annexb: boolean()) ::
          {:ok, non_neg_integer(), t()} | {:error, :end_of_stream}
  def new(device, stream, start_date, opts \\ []) do
    %__MODULE__{
      device: device,
      stream: stream,
      start_date: start_date,
      annexb?: Keyword.get(opts, :annexb, true)
    }
    |> open_next_file()
    |> case do
      :end_of_stream -> {:error, :end_of_stream}
      :codec_changed -> {:error, :codec_changed}
      {offset, state} -> {:ok, offset, state}
    end
  end

  @spec tracks(t()) :: [Track.t()]
  def tracks(%__MODULE__{tracks: tracks_details}) do
    Map.values(tracks_details) |> Enum.map(&%{&1.track | timescale: @video_timescale})
  end

  @spec next_sample(t(), Track.id()) ::
          {:ok, {ExMP4.Sample.t(), DateTime.t()}, t()} | {:error, :end_of_stream}
  def next_sample(%__MODULE__{} = state, track_id) do
    track_details = Map.fetch!(state.tracks, track_id)
    %{reducer: reducer, bit_stream_filter: filter, track: track} = track_details
    %{reader: reader, current_recording: recording} = state
    timescale = track.timescale

    case reducer.({:cont, nil}) do
      {:suspended, sample_metadata, new_reducer} ->
        sample = read_sample(reader, sample_metadata, filter)

        dts_in_ms = timescalify(sample.dts, timescale, :millisecond)
        sample_timestamp = DateTime.add(recording.start_date, dts_in_ms, :millisecond)

        sample = %{
          sample
          | dts: timescalify(sample.dts, timescale, @video_timescale) + track_details.offset,
            pts: timescalify(sample.pts, timescale, @video_timescale) + track_details.offset,
            duration: timescalify(sample.duration, timescale, @video_timescale)
        }

        track_details = %{track_details | reducer: new_reducer}
        state = %__MODULE__{state | tracks: Map.put(state.tracks, track_id, track_details)}

        {:ok, {sample, sample_timestamp}, state}

      {:done, nil} ->
        # For now we only have one track, once we add support
        # for audio tracks we should first make sure that
        # all tracks are finished before opening a new file
        case open_next_file(state) do
          :end_of_stream -> {:error, :end_of_stream}
          :codec_changed -> {:error, :codec_changed}
          {_offset, state} -> next_sample(state, track_id)
        end
    end
  end

  @spec close(t()) :: :ok
  def close(%__MODULE__{reader: nil}), do: :ok
  def close(%__MODULE__{reader: reader}), do: Reader.close(reader)

  defp open_next_file(%__MODULE__{recordings: []} = state) do
    start_date =
      if state.current_recording,
        do: state.current_recording.end_date,
        else: state.start_date

    recordings =
      Recordings.get_recordings_between(
        state.device.id,
        state.stream,
        start_date,
        @default_end_date
      )

    case recordings do
      [] -> :end_of_stream
      _ -> %{state | recordings: recordings} |> maybe_update_start_date() |> open_next_file()
    end
  end

  defp open_next_file(%__MODULE__{recordings: [recording | recordings]} = state) do
    if state.reader, do: Reader.close(state.reader)
    reader = Recordings.recording_path(state.device, state.stream, recording) |> Reader.new!()

    state = %__MODULE__{
      state
      | reader: reader,
        recordings: recordings,
        current_recording: recording
    }

    tracks =
      Reader.tracks(reader)
      |> Enum.filter(&(&1.type == :video))
      |> Map.new(&build_track_details(state, &1))

    offset =
      Map.values(tracks)
      |> Enum.min_by(& &1.offset_from_start_date)
      |> then(&timescalify(&1.offset_from_start_date, &1.track.timescale, :millisecond))

    old_tracks = Map.values(state.tracks) |> Enum.map(& &1.track)
    new_tracks = Map.values(tracks) |> Enum.map(& &1.track)

    case compare_tracks(old_tracks, new_tracks) do
      {:error, :codec_changed} -> :codec_changed
      :ok -> {offset, %__MODULE__{state | tracks: tracks}}
    end
  end

  defp build_track_details(%__MODULE__{} = state, track) do
    bit_stream_filter =
      case state.annexb? do
        true ->
          {:ok, bit_stream_filter} = ExMP4.BitStreamFilter.MP4ToAnnexb.init(track, [])
          bit_stream_filter

        false ->
          nil
      end

    track_details =
      %{track: track, bit_stream_filter: bit_stream_filter}
      |> maybe_seek(state)
      |> set_track_duration(state)
      |> update_offset(state)

    {track.id, track_details}
  end

  defp maybe_seek(%{track: track} = track_details, state) do
    %{current_recording: recording, start_date: start_date} = state

    reducer = &Enumerable.reduce(track, &1, fn elem, _acc -> {:suspend, elem} end)

    case DateTime.compare(recording.start_date, start_date) do
      :lt ->
        offset =
          start_date
          |> DateTime.diff(recording.start_date, :millisecond)
          |> timescalify(:millisecond, track.timescale)

        keyframe_dts =
          state.reader
          |> Reader.stream(tracks: [track.id])
          |> Enum.reduce_while(0, fn metadata, acc ->
            # credo:disable-for-next-line
            cond do
              metadata.sync? -> {:cont, metadata.dts}
              metadata.dts >= offset -> {:halt, acc}
              true -> {:cont, acc}
            end
          end)

        track_details
        |> Map.put(:reducer, read_until(reducer, keyframe_dts))
        |> Map.put(:offset_from_start_date, offset - keyframe_dts)
        |> Map.put(:offset, timescalify(keyframe_dts, track.timescale, @video_timescale))

      _other ->
        Map.merge(track_details, %{reducer: reducer, offset: 0, offset_from_start_date: 0})
    end
  end

  defp set_track_duration(track_details, %{current_recording: recording}) do
    DateTime.diff(recording.end_date, recording.start_date, :microsecond)
    |> timescalify(:microsecond, @video_timescale)
    |> then(&Map.put(track_details, :track_duration, &1))
  end

  defp update_offset(%{track: track} = track_details, state) do
    {old_duration, old_offset} =
      case state.tracks[track.id] do
        nil -> {0, -track_details.offset}
        old_track -> {old_track.track_duration, old_track.offset}
      end

    Map.put(track_details, :offset, old_offset + old_duration)
  end

  defp read_until(reducer, dts) do
    {:suspended, sample_metadata, new_reducer} = reducer.({:cont, nil})

    if sample_metadata.dts == dts do
      reducer
    else
      read_until(new_reducer, dts)
    end
  end

  defp read_sample(reader, sample_metadata, nil) do
    Reader.read_sample(reader, sample_metadata)
  end

  defp read_sample(reader, sample_metadata, filter) do
    {sample, _bit_stream_filter} =
      reader
      |> Reader.read_sample(sample_metadata)
      |> then(&BitStreamFilter.MP4ToAnnexb.filter(filter, &1))

    sample
  end

  defp compare_tracks([], _new_tracks), do: :ok

  defp compare_tracks(old_tracks, new_tracks) do
    old_video_track = Enum.find(old_tracks, &(&1.type == :video))
    new_video_track = Enum.find(new_tracks, &(&1.type == :video))

    if old_video_track.media != new_video_track.media do
      {:error, :codec_changed}
    else
      :ok
    end
  end

  defp maybe_update_start_date(%{current_recording: nil} = state) do
    first_recording_start_date = hd(state.recordings).start_date

    case DateTime.compare(state.start_date, first_recording_start_date) do
      :lt -> %{state | start_date: first_recording_start_date}
      _other -> state
    end
  end

  defp maybe_update_start_date(state), do: state
end
