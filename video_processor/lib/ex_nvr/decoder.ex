defmodule ExNVR.AV.Decoder do
  @moduledoc false

  alias ExNVR.AV.Frame
  alias ExNVR.AV.VideoProcessor.NIF

  @type codec() :: :h264 | :hevc

  @type t() :: reference()

  @default_codec_options [out_format: nil, out_width: -1, out_height: -1]

  @spec new(codec(), keyword()) :: t()
  def new(codec, opts \\ []) when codec in [:h264, :hevc] do
    opts = Keyword.merge(@default_codec_options, opts)
    NIF.new_decoder(codec, opts[:out_width], opts[:out_height], opts[:out_format])
  end

  @spec decode(t(), binary(), pts: integer(), dts: integer()) :: [Frame.t()]
  def decode(decoder, data, opts \\ []) do
    pts = opts[:pts] || 0
    dts = opts[:dts] || 0

    decoder
    |> NIF.decode(data, pts, dts)
    |> Enum.map(fn {data, format, width, height, pts} ->
      Frame.new(data, format: format, width: width, height: height, pts: pts)
    end)
  end

  @spec flush(t()) :: [Frame.t()]
  def flush(decoder) do
    decoder
    |> NIF.flush_decoder()
    |> Enum.map(fn {data, format, width, height, pts} ->
      Frame.new(data, format: format, width: width, height: height, pts: pts)
    end)
  end
end
