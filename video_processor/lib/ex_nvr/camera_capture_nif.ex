defmodule ExNVR.AV.CameraCapture.NIF do
  @moduledoc false

  @compile {:autoload, false}
  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"libcameracapture")
    :ok = :erlang.load_nif(path, 0)
  end

  def open_camera(_url, _framerate, _width, _height), do: :erlang.nif_error(:undef)
  def read_camera_frame(_native), do: :erlang.nif_error(:undef)
end
