defmodule ExNVR.Recordings.Snapshooter do
  @moduledoc """
  Get a snapshot from a recording
  """

  alias ExNVR.Model.{Device, Recording}
  alias ExNVR.MP4.Reader
  alias Membrane.{Buffer, H264, H265}
  alias Membrane.H264.FFmpeg.Decoder, as: H264Decoder
  alias Membrane.H265.FFmpeg.Decoder, as: H265Decoder
  alias Membrane.Time

  @spec snapshot(Device.t(), Recording.t(), DateTime.t(), Keyword.t()) ::
          {:ok, DateTime.t(), binary()} | {:error, term()}
  def snapshot(%Device{} = device, %Recording{} = recording, datetime, opts \\ []) do
    method = Keyword.get(opts, :method, :before)
    path = ExNVR.Recordings.recording_path(device, recording)
    seek_time = Time.from_datetime(datetime) - Time.from_datetime(recording.start_date)

    with {:ok, mp4_reader} <- Reader.new(path),
         {track_id, track} <- Reader.get_video_track(mp4_reader),
         mp4_reader <- Reader.seek_file(mp4_reader, track_id, seek_time),
         {_reader, frames} <- read_frames(mp4_reader, track_id, method, seek_time),
         {:ok, snapshot} <- do_get_snapshot(frames, track) do
      Reader.close(mp4_reader)

      start_date =
        if method == :before do
          DateTime.add(
            recording.start_date,
            Time.as_milliseconds(List.first(frames).dts, :round),
            :millisecond
          )
        else
          datetime
        end

      {:ok, start_date, snapshot}
    else
      nil -> {:error, :no_video_track}
      other -> other
    end
  end

  defp read_frames(reader, track_id, method, max_dts) do
    do_read_frames(method, reader, track_id, max_dts, [])
  end

  defp do_read_frames(:precise, reader, track_id, max_dts, frames) do
    case Reader.read_packet(reader, track_id) do
      {reader, _track_id, buffer} ->
        if buffer.dts >= max_dts do
          {reader, Enum.reverse([buffer | frames])}
        else
          do_read_frames(:precise, reader, track_id, max_dts, [buffer | frames])
        end

      :eof ->
        {reader, Enum.reverse(frames)}
    end
  end

  defp do_read_frames(:before, reader, track_id, _max_dts, _frames) do
    {reader, _track_id, frame} = Reader.read_packet(reader, track_id)
    {reader, [frame]}
  end

  defp do_get_snapshot(frames, track) do
    decoder_module = get_decoder(track)
    decoder = decoder_module.create!()

    [first_frame | rest] =
      Enum.map(frames, fn frame -> %Buffer{frame | payload: to_annexb(frame.payload)} end)

    first_frame = %Buffer{first_frame | payload: get_parameter_sets(track) <> first_frame.payload}

    last_frame =
      Enum.reduce([first_frame | rest], nil, fn frame, _last_frame ->
        {:ok, _pts, decoded_frames} =
          decoder_module.decode(frame.payload, frame.pts, frame.dts, false, decoder)

        List.last(decoded_frames)
      end)

    last_frame =
      case decoder_module.flush(false, decoder) do
        {:ok, _pts, []} -> last_frame
        {:ok, _pts, frames} -> List.last(frames)
      end

    Turbojpeg.yuv_to_jpeg(last_frame, track.width, track.height, 75, :I420)
  end

  defp get_parameter_sets(%H264{stream_structure: {_avc, dcr}}) do
    %{spss: spss, ppss: ppss} = H264.DecoderConfigurationRecord.parse(dcr)
    Enum.map_join(spss ++ ppss, &(<<0, 0, 0, 1>> <> &1))
  end

  defp get_parameter_sets(%H265{stream_structure: {_hevc, dcr}}) do
    %{vpss: vpss, spss: spss, ppss: ppss} = H265.DecoderConfigurationRecord.parse(dcr)
    Enum.map_join(vpss ++ spss ++ ppss, &(<<0, 0, 0, 1>> <> &1))
  end

  defp get_decoder(%H264{}), do: H264Decoder.Native
  defp get_decoder(%H265{}), do: H265Decoder.Native

  defp to_annexb(data) do
    for <<size::32, nal_unit::binary-size(size) <- data>>,
      into: <<>>,
      do: <<0, 0, 0, 1, nal_unit::binary>>
  end
end
