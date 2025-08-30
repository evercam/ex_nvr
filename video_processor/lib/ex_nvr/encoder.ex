defmodule ExNVR.AV.Encoder do
  @moduledoc false

  alias ExNVR.AV.VideoProcessor.NIF

  @type t :: reference()

  @type codec :: :h264 | :mjpeg
  @type encoder_options :: [
          {:width, non_neg_integer()}
          | {:height, non_neg_integer()}
          | {:format, atom()}
          | {:time_base, {non_neg_integer(), non_neg_integer()}}
          | {:gop_size, non_neg_integer()}
          | {:max_b_frames, non_neg_integer()}
          | {:profile, String.t()}
        ]

  @spec new(codec(), encoder_options()) :: t()
  def new(codec, opts) when codec in [:h264, :mjpeg] do
    {time_base_num, time_base_den} = opts[:time_base]

    nif_options =
      opts
      |> Map.new()
      |> Map.delete(:time_base)
      |> Map.merge(%{time_base_num: time_base_num, time_base_den: time_base_den})

    NIF.new_encoder(codec, nif_options)
  end

  @spec encode(t(), ExNVR.AV.Frame.t()) :: [ExNVR.AV.Packet.t()]
  def encode(encoder, frame) do
    encoder
    |> NIF.encode(frame.data, frame.pts)
    |> to_packets()
  end

  @doc """
  Flush the encoder.
  """
  @spec flush(t()) :: [ExNVR.AV.Packet.t()]
  def flush(encoder) do
    encoder
    |> NIF.flush_encoder()
    |> to_packets()
  end

  defp to_packets(result) do
    Enum.map(result, fn {data, dts, pts, keyframe?} ->
      %ExNVR.AV.Packet{data: data, dts: dts, pts: pts, keyframe?: keyframe?}
    end)
  end
end
