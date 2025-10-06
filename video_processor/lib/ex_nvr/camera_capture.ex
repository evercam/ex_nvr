defmodule ExNVR.AV.CameraCapture do
  @moduledoc false

  alias ExNVR.AV.CameraCapture.NIF
  alias ExNVR.AV.Frame

  @spec open_camera(String.t(), String.t()) :: {:ok, reference()} | {:error, term()}
  def open_camera(device_url, framerate) do
    NIF.open_camera(device_url, framerate)
  end

  @spec read_camera_frame(reference()) :: {:ok, Frame.t()} | {:error, term()}
  def read_camera_frame(native) do
    case NIF.read_camera_frame(native) do
      {:ok, {payload, pix_fmt, widht, height, pts}} ->
        frame =
          Frame.new(payload,
            type: :video,
            format: pix_fmt,
            width: widht,
            height: height,
            pts: pts
          )

        {:ok, frame}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
