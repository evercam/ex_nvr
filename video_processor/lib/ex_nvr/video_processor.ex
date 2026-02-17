defmodule ExNVR.AV.VideoProcessor do
  @moduledoc false

  alias ExNVR.AV.Encoder
  alias ExNVR.AV.VideoProcessor.NIF

  @spec encode_to_jpeg(ExNVR.AV.Frame.t()) :: binary()
  def encode_to_jpeg(frame) do
    encoder =
      Encoder.new(:mjpeg,
        width: frame.width,
        height: frame.height,
        time_base: {1, 30},
        format: :yuvj420p
      )

    encoder
    |> Encoder.encode(frame)
    |> Kernel.++(Encoder.flush(encoder))
    |> hd()
    |> Map.get(:data)
  end

  @spec new_converter(keyword()) :: reference()
  def new_converter(opts) do
    pad = if Keyword.get(opts, :pad?, false), do: 1, else: 0

    NIF.new_converter(
      opts[:in_width],
      opts[:in_height],
      opts[:in_format],
      opts[:out_width],
      opts[:out_height],
      opts[:out_format],
      pad
    )
  end

  @spec convert(reference(), binary()) :: binary()
  def convert(converter, data) do
    {data, _w, _h, _fmt, _pts} = NIF.convert(converter, data)
    data
  end
end
