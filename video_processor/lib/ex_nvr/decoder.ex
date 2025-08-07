defmodule ExNVR.AV.Decoder do
  @moduledoc false

  alias ExNVR.AV.Frame
  alias ExNVR.AV.VideoProcessor.NIF

  @type codec() :: :h264 | :hevc

  @type t() :: reference()

  @spec new(codec()) :: t()
  def new(codec) when codec in [:h264, :hevc] do
    NIF.new_decoder(codec)
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
