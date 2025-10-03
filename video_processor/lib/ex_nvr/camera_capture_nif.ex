defmodule ExNVR.AV.CameraCapture.NIF do
  @moduledoc false
  @compile {:autoload, false}
  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"camera_capture")

    # path = Path.expand("priv/camera_capture")
    :ok = :erlang.load_nif(path, 0)
  end

  # webcam
  def open_camera(_url, _framerate), do: :erlang.nif_error(:undef)
  def read_camera_frame(_native), do: :erlang.nif_error(:undef)
  def camera_stream_props(_native), do: :erlang.nif_error(:undef)
end
