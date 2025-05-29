defmodule ExNVR.Decoder.H264 do
  @moduledoc """
  Implementation of `ExNVR.Decoder` behaviour to decode h264 video stream.
  """

  use ExNVR.Decoder

  alias Membrane.Buffer
  alias Membrane.H264.FFmpeg.Decoder

  @impl true
  def init, do: Decoder.Native.create()

  @impl true
  def decode(decoder, buffer) do
    dts = Buffer.get_dts_or_pts(buffer)

    case Decoder.Native.decode(buffer.payload, buffer.pts, dts, false, decoder) do
      {:ok, pts, decoded_frames} -> {:ok, map_to_buffers(pts, decoded_frames)}
      error -> error
    end
  end

  @impl true
  def flush(decoder) do
    case Decoder.Native.flush(false, decoder) do
      {:ok, pts, decoded_frames} -> {:ok, map_to_buffers(pts, decoded_frames)}
      error -> error
    end
  end

  defp map_to_buffers(pts, frames) do
    pts
    |> Enum.zip(frames)
    |> Enum.map(fn {pts, payload} -> %Buffer{payload: payload, pts: pts} end)
  end
end
