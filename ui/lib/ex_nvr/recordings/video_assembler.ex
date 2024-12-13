defmodule ExNVR.Recordings.VideoAssembler do
  @moduledoc """
  Assemble videos segments (chunks) into one file.
  """

  import ExMP4.Helper

  alias ExMP4.{Reader, Writer}

  @spec assemble([{Path.t(), DateTime.t()}], DateTime.t(), DateTime.t(), pos_integer(), Path.t()) ::
          DateTime.t()
  def assemble(files, start_date, end_date, duration, dest) do
    File.rm!(dest)

    state = %{
      writer: Writer.new!(dest),
      reader: nil,
      out_track: nil,
      in_track: nil,
      start_date: DateTime.to_unix(start_date, :millisecond),
      end_date: DateTime.to_unix(end_date, :millisecond),
      target_duration: duration
    }

    state =
      Enum.reduce_while(files, state, fn {path, start_date}, state ->
        state
        |> Map.put(:reader, Reader.new!(path))
        |> maybe_init_tracks()
        |> do_handle_file(DateTime.to_unix(start_date, :millisecond))
      end)

    :ok = Writer.write_trailer(state.writer)

    state.start_date
    |> timescalify(state.out_track.timescale, :millisecond)
    |> DateTime.from_unix!(:millisecond)
  end

  defp maybe_init_tracks(%{out_track: nil} = state) do
    in_track = video_track(state.reader)

    writer = state.writer |> Writer.add_track(in_track) |> Writer.write_header()
    out_track = writer |> Writer.tracks() |> List.first()

    start_date = timescalify(state.start_date, :millisecond, out_track.timescale)
    end_date = timescalify(state.end_date, :millisecond, out_track.timescale)
    target_duration = timescalify(state.target_duration, :second, out_track.timescale)

    %{
      state
      | writer: writer,
        out_track: out_track,
        in_track: in_track,
        start_date: start_date,
        end_date: end_date,
        target_duration: target_duration
    }
  end

  defp maybe_init_tracks(state) do
    %{state | in_track: video_track(state.reader)}
  end

  defp do_handle_file(state, file_start_date) do
    %{in_track: in_track, out_track: out_track, reader: reader} = state
    file_start_date = timescalify(file_start_date, :millisecond, out_track.timescale)
    {min_dts, max_dts} = min_max_dts(state, file_start_date)

    state =
      Reader.stream(reader, tracks: [in_track.id])
      |> filter_by_dts(min_dts, max_dts)
      |> Reader.samples(reader)
      |> Stream.map(&update_sample(&1, in_track, out_track))
      |> Enum.into(state.writer)
      |> then(&%{state | writer: &1})
      |> maybe_update_start_date(min_dts, file_start_date)

    Reader.close(reader)

    case max_dts do
      nil -> {:cont, state}
      _value -> {:halt, state}
    end
  end

  defp video_track(reader), do: reader |> Reader.tracks() |> Enum.find(&(&1.type == :video))

  defp update_sample(sample, in_track, out_track) do
    %{
      sample
      | track_id: out_track.id,
        dts: timescalify(sample.dts, in_track.timescale, out_track.timescale),
        pts: timescalify(sample.pts, in_track.timescale, out_track.timescale),
        duration: timescalify(sample.duration, in_track.timescale, out_track.timescale)
    }
  end

  defp min_max_dts(state, file_start_date) do
    %{in_track: in_track, out_track: out_track} = state

    in_track_duration = ExMP4.Track.duration(in_track, out_track.timescale)

    # first file: start at the provided date
    min_dts =
      if file_start_date < state.start_date do
        diff = state.start_date - file_start_date
        offset = timescalify(diff, out_track.timescale, in_track.timescale)
        seek_keyframe(state.reader, offset)
      end

    # check if we hit the end date
    max_dts1 =
      if file_start_date + in_track_duration >= state.end_date do
        timescalify(state.end_date - file_start_date, out_track.timescale, in_track.timescale)
      end

    # check if we hit the provided duration
    duration = get_duration(state.writer, state.out_track.id)

    max_dts2 =
      if duration + in_track_duration >= state.target_duration do
        timescalify(state.target_duration - duration, out_track.timescale, in_track.timescale)
      end

    max_dts =
      cond do
        is_nil(max_dts1) and is_nil(max_dts2) -> nil
        is_nil(max_dts1) -> max_dts2
        is_nil(max_dts2) -> max_dts1
        true -> min(max_dts1, max_dts2)
      end

    {min_dts, max_dts}
  end

  defp seek_keyframe(reader, offset) do
    reader
    |> Reader.stream()
    |> Enum.reduce_while(0, fn metadata, acc ->
      cond do
        metadata.dts >= offset -> {:halt, acc}
        metadata.sync? -> {:cont, metadata.dts}
        true -> {:cont, acc}
      end
    end)
  end

  defp filter_by_dts(stream, nil, nil), do: stream
  defp filter_by_dts(stream, min_dts, nil), do: Stream.filter(stream, &(&1.dts >= min_dts))
  defp filter_by_dts(stream, nil, max_dts), do: Stream.filter(stream, &(&1.dts <= max_dts))

  defp filter_by_dts(stream, min_dts, max_dts),
    do: Stream.filter(stream, &(&1.dts >= min_dts and &1.dts <= max_dts))

  defp get_duration(writer, track_id) do
    Writer.tracks(writer)
    |> Enum.find(&(&1.id == track_id))
    |> ExMP4.Track.duration()
  end

  defp maybe_update_start_date(state, nil, _file_start_date), do: state

  defp maybe_update_start_date(state, min_dts, file_start_date) do
    min_dts = timescalify(min_dts, state.in_track.timescale, state.out_track.timescale)
    extra_duration = state.start_date - file_start_date - min_dts

    %{
      state
      | start_date: file_start_date + min_dts,
        target_duration: state.target_duration + extra_duration
    }
  end
end
