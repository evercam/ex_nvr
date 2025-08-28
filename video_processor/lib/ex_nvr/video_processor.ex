defmodule ExNVR.AV.VideoProcessor do
  @moduledoc false

  alias ExNVR.AV.Encoder

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
end
