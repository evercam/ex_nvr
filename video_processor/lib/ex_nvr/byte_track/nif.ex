defmodule ExNVR.AV.ByteTrack.NIF do
  @moduledoc false

  @compile {:autoload, false}
  @on_load :load_nif

  require Logger

  def load_nif do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"libbytetrack")

    case :erlang.load_nif(path, 0) do
      :ok ->
        :persistent_term.put({__MODULE__, :loaded}, true)
        :ok

      {:error, reason} ->
        :persistent_term.put({__MODULE__, :loaded}, false)
        Logger.warning("ByteTrack NIF not loaded: #{inspect(reason)}")
        :ok
    end
  end

  def loaded?, do: :persistent_term.get({__MODULE__, :loaded}, false)

  def create_tracker, do: :erlang.nif_error(:nif_not_loaded)

  def update(_detections, _tracker), do: :erlang.nif_error(:nif_not_loaded)
end
