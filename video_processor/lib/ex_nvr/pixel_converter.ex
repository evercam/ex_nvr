defmodule ExNVR.AV.PixelConverter do
  @moduledoc false

  alias ExNVR.AV.VideoProcessor.NIF

  @spec create_converter(pos_integer(), pos_integer(), String.t(), String.t()) ::
          {:ok, reference()} | {:error, String.t()}
  def create_converter(width, height, old_format, new_format) do
    case NIF.create_converter(width, height, old_format, new_format) do
      {:ok, state} -> {:ok, state}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "nif_failed"}
    end
  end

  @spec convert_pixels(reference(), binary()) :: {:ok, binary()} | {:error, String.t()}
  def convert_pixels(state, binary) do
    case NIF.convert_pixel(state, binary) do
      {:ok, out} -> {:ok, out}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "nif_failed"}
    end
  end
end
