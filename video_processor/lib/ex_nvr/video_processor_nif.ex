defmodule ExNVR.AV.VideoProcessor.NIF do
  @moduledoc false

  @compile {:autoload, false}
  @on_load :__on_load__

  def __on_load__ do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"libvideoprocessor")
    :ok = :erlang.load_nif(path, 0)
  end

  def new_encoder(_codec, _params), do: :erlang.nif_error(:undef)

  def new_decoder(_codec, _out_width, _out_height, _out_format, _pad?),
    do: :erlang.nif_error(:undef)

  def encode(_encoder, _data, _pts), do: :erlang.nif_error(:undef)

  def decode(_decoder, _data, _dts, _pts), do: :erlang.nif_error(:undef)

  def flush_encoder(_encoder), do: :erlang.nif_error(:undef)

  def flush_decoder(_decoder), do: :erlang.nif_error(:undef)
end
