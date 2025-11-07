defmodule ExNVR.AV.ByteTrack.NIF do
  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"libbytetrack")

    case :erlang.load_nif(path, 0) do
      :ok -> :ok
      {:error, reason} -> raise "failed to load NIF library, reason: #{inspect(reason)}"
    end
  end

  def create_tracker() do
    :erlang.nif_error(:nif_not_loaded)
  end

  def update(_detections, _tracker) do
    :erlang.nif_error(:nif_not_loaded)
  end
end
