defmodule ExNVR.Pipeline.Source.File do
  @moduledoc false

  use Membrane.Source

  require Membrane.Logger

  alias ExMP4.BitStreamFilter.MP4ToAnnexb
  alias ExMP4.{Helper, Reader}
  alias ExNVR.Model.Device
  alias Membrane.{Buffer, H264, H265}

  def_options device: [
                spec: Device.t(),
                description: "The file device"
              ]

  def_output_pad :main_stream_output,
    accepted_format: any_of(%H264{alignment: :au}, %H265{alignment: :au}),
    flow_control: :push,
    availability: :on_request

  @impl true
  def handle_init(_ctx, options) do
    Membrane.Logger.info("Start streaming file: #{Device.file_location(options.device)}")

    reader = Reader.new!(Device.file_location(options.device))

    state = %{
      reader: reader,
      tracks: init_tracks(reader)
    }

    {[], state}
  end

  @impl true
  def handle_setup(_ctx, state) do
    actions =
      Enum.map(state.tracks, fn {track_id, %{track: track}} ->
        media_track = ExNVR.Pipeline.Track.new(track.type, track.media)
        {:notify_parent, {:main_stream, %{track_id => media_track}}}
      end)

    {actions, state}
  end

  @impl true
  def handle_pad_added(Pad.ref(:main_stream_output, track_id) = pad, _ctx, state) do
    %{pad: nil, track: track} = Map.fetch!(state.tracks, track_id)

    Process.send_after(self(), {:send_frame, track_id}, 0)
    track_details = put_in(state.tracks, [track_id, :pad], pad)

    {[
       stream_format: {pad, generate_stream_format(track)}
     ], %{state | tracks: track_details}}
  end

  @impl true
  def handle_info({:send_frame, track_id}, _ctx, state) do
    %{current_sample: sample} = track_details = Map.fetch!(state.tracks, track_id)

    time = Helper.timescalify(sample.duration, track_details.track.timescale, :millisecond)
    Process.send_after(self(), {:send_frame, track_id}, time)

    buffer =
      map_sample_to_buffer(
        sample,
        track_details.track,
        track_details.offset
      )

    state = put_in(state, [:tracks, track_id], next_sample(track_details, state.reader))

    {[buffer: {track_details.pad, buffer}], state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    :ok = Reader.close(state.reader)
    {[terminate: :normal], state}
  end

  defp init_tracks(reader) do
    reader
    |> Reader.tracks()
    |> Enum.filter(&(&1.type == :video))
    |> Enum.reduce(%{}, fn track, acc ->
      {:suspended, sample_metadata, reducer} =
        Enumerable.reduce(track, {:cont, nil}, fn elem, _acc -> {:suspend, elem} end)

      {:ok, bit_stream_filter} = MP4ToAnnexb.init(track, [])

      track_details = %{
        track: track,
        reducer: reducer,
        current_sample: get_sample(reader, bit_stream_filter, sample_metadata),
        pad: nil,
        offset: 0,
        bit_stream_filter: bit_stream_filter
      }

      Map.put(acc, track.id, track_details)
    end)
  end

  defp next_sample(%{track: track} = track_details, reader) do
    {sample_metadata, reducer, offset} =
      case track_details.reducer.({:cont, nil}) do
        {:done, _acc} ->
          {:suspended, sample_metadata, reducer} =
            Enumerable.reduce(track, {:cont, nil}, fn sample, _acc ->
              {:suspend, sample}
            end)

          new_offset = track_details.offset + ExMP4.Track.duration(track, :nanosecond)
          {sample_metadata, reducer, new_offset}

        {:suspended, sample_metadata, reducer} ->
          {sample_metadata, reducer, track_details.offset}
      end

    %{
      track_details
      | current_sample: get_sample(reader, track_details.bit_stream_filter, sample_metadata),
        reducer: reducer,
        offset: offset
    }
  end

  defp get_sample(reader, bit_stream_filter, sample_metadata) do
    reader
    |> Reader.read_sample(sample_metadata)
    |> then(&MP4ToAnnexb.filter(bit_stream_filter, &1))
    |> elem(0)
  end

  defp map_sample_to_buffer(sample, track, offset) do
    %Buffer{
      payload: sample.payload,
      dts: offset + Helper.timescalify(sample.dts, track.timescale, :nanosecond),
      pts: offset + Helper.timescalify(sample.pts, track.timescale, :nanosecond),
      metadata: %{
        track.media => %{key_frame?: sample.sync?},
        timestamp: System.os_time(:millisecond)
      }
    }
  end

  defp generate_stream_format(track) do
    case track.media do
      :h264 -> %H264{alignment: :au, width: track.width, height: track.height}
      :h265 -> %H265{alignment: :au, width: track.width, height: track.height}
    end
  end
end
