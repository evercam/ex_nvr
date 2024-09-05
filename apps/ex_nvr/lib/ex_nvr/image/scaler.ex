defmodule ExNVR.Image.Scaler do
  @moduledoc """
  Scale images to a given width and height.
  """

  alias Membrane.FFmpeg.SWScale.Scaler

  def new(input_width, input_height, output_width, output_height) do
    Scaler.Native.create(input_width, input_height, output_width, output_height)
  end

  def new!(input_width, input_height, output_width, output_height) do
    case new(input_width, input_height, output_width, output_height) do
      {:ok, scaler} -> scaler
      {:error, reason} -> raise "Could not create scaler: #{inspect(reason)}"
    end
  end

  def scale(scaler, yuv_image) do
    Scaler.Native.scale(yuv_image, false, scaler)
  end
end
