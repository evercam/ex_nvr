defmodule ExNVR.AV.Encoder.NIF do
  @moduledoc false

  @compile {:autoload, false}
  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"libvideoprocessor")
    :ok = :erlang.load_nif(path, 0)
  end

  def new(_codec, _params), do: :erlang.nif_error(:undef)

  def encode(_encoder, _data, _pts), do: :erlang.nif_error(:undef)

  def flush(_encoder), do: :erlang.nif_error(:undef)
end
