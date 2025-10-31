defmodule ExNVR.AV.CameraCapture do
  @moduledoc false

  alias ExNVR.AV.CameraCapture.NIF
  alias ExNVR.AV.Frame

  @spec open_camera(String.t(), non_neg_integer(), integer(), integer()) ::
          {:ok, reference()} | {:error, term()}
  def open_camera(device_url, framerate, width, height) do
    NIF.open_camera(device_url, to_string(framerate), width, height)
  end

  @spec read_camera_frame(reference()) :: {:ok, Frame.t()} | {:error, term()}
  def read_camera_frame(native) do
    case NIF.read_camera_frame(native) do
      {:ok, {payload, pix_fmt, width, height, pts}} ->
        frame =
          Frame.new(payload,
            type: :video,
            format: pix_fmt,
            width: width,
            height: height,
            pts: pts
          )

        {:ok, frame}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
