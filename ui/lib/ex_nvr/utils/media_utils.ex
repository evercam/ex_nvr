defmodule ExNVR.MediaUtils do
  @moduledoc false

  alias Membrane.Buffer

  @default_video_timescale 90_000

  @spec decode_last(Enumerable.t(Buffer.t() | ExMP4.Sample.t()), Xav.Decoder.t()) :: Buffer.t()
  def decode_last(buffers, decoder) do
    buffers
    |> Stream.transform(
      fn -> decoder end,
      fn packet, decoder ->
        case Xav.Decoder.decode(decoder, packet.payload, pts: packet.pts) do
          {:ok, frame} -> {[frame], decoder}
          _other -> {[], decoder}
        end
      end,
      &Xav.Decoder.flush!/1
    )
    |> Enum.reverse()
    |> hd()
  end

  @spec track_from_stream_format(module()) :: ExMP4.Track.t()
  def track_from_stream_format(stream_format) do
    media =
      case stream_format do
        %Membrane.H264{} -> :h264
        %Membrane.H265{} -> :h265
      end

    %ExMP4.Track{
      type: :video,
      media: media,
      width: stream_format.width,
      height: stream_format.height,
      timescale: @default_video_timescale
    }
  end

  @spec to_annexb(binary() | [binary()]) :: binary()
  def to_annexb(au) when is_list(au), do: Enum.map_join(au, &<<1::32, &1::binary>>)
  def to_annexb(au), do: au
end
