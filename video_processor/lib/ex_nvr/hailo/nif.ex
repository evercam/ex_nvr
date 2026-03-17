defmodule ExNVR.AV.Hailo.NIF.Macro do
  defmacro defnif(call) do
    {name, _, args} = call

    quote do
      def unquote(name)(unquote_splicing(args)) do
        :erlang.nif_error(:nif_not_loaded)
      end
    end
  end
end

defmodule ExNVR.AV.Hailo.NIF do
  @moduledoc false

  @compile {:autoload, false}
  @on_load :load_nif

  require Logger

  import ExNVR.AV.Hailo.NIF.Macro

  def load_nif do
    path = :filename.join(:code.priv_dir(:video_processor), ~c"libhailo")

    case :erlang.load_nif(path, 0) do
      :ok ->
        :persistent_term.put({__MODULE__, :loaded}, true)
        :ok

      {:error, reason} ->
        :persistent_term.put({__MODULE__, :loaded}, false)
        Logger.warning("Hailo NIF not loaded: #{inspect(reason)}")
        :ok
    end
  end

  def loaded? do
    :persistent_term.get({__MODULE__, :loaded}, false)
  end

  defnif(create_vdevice())
  defnif(configure_network_group(_vdevice_ref, _hef_path))
  defnif(create_pipeline(_network_group_ref))
  defnif(get_input_vstream_infos_from_ng(_network_group_ref))
  defnif(get_output_vstream_infos_from_ng(_network_group_ref))
  defnif(get_input_vstream_infos_from_pipeline(_pipeline_ref))
  defnif(get_output_vstream_infos_from_pipeline(_pipeline_ref))
  defnif(infer(_pipeline_ref, _input_data))
end
