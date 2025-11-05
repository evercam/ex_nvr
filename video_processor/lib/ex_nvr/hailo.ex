defmodule ExNVR.AV.Hailo do
  @moduledoc """
  Interface for interacting with Hailo accelerators.

  This module provides high-level functions for loading models and running inference
  using Hailo AI accelerators through HailoRT.
  NOTE: This module provides a more direct NIF interaction layer.
  For a more user-friendly, higher-level API, see the main `NxHailo` module.
  """

  alias ExNVR.AV.Hailo.Model
  alias ExNVR.AV.Hailo.API

  @doc """
  Loads a Hailo model from a HEF file and prepares it for inference.

  This function handles VDevice creation, network configuration, and pipeline setup.

  Parameters:
    - `hef_path`: The path to the .hef model file.
    - `model_name` (optional): A name to associate with the loaded model.

  Returns `{:ok, %NxHailo.Model{}}` or `{:error, reason}`.
  """
  def load(hef_path) when is_binary(hef_path) do
    with {:ok, vdevice} <- API.create_vdevice(),
         {:ok, ng} <- API.configure_network_group(vdevice, hef_path),
         {:ok, pipeline_struct} <- API.create_pipeline(ng) do
      model = %ExNVR.AV.Hailo.Model{
        pipeline: pipeline_struct,
        name: Path.basename(hef_path)
      }

      {:ok, model}
    end
  end

  @doc """
  Runs inference on a previously loaded Hailo model.

  Parameters:
    - `model`: The `%NxHailo.Model{}` struct obtained from `load/1`.
    - `inputs`: A map where keys correspond to the input vstream names, and the values are `Nx.Tensor`s.
      Example: `%{ "input_layer_name" => #Nx.Tensor<...> }`
    - `output_parser`: The module that implements the `NxHailo.Hailo.OutputParser` behaviour
    - `output_parser_opts`: A keyword list of options to pass to the output parser.

  Returns `{:ok, output_data_map}` or `{:error, reason}`.
  The `output_data_map` will have string keys for output vstream names.
  """
  def infer(
        %Model{pipeline: %API.Pipeline{} = pipeline},
        inputs,
        output_parser,
        output_parser_opts \\ []
      )
      when is_map(inputs) and is_atom(output_parser) do
    # The API.infer function expects string keys for input map.
    # We can be flexible and convert atom keys here if necessary,
    # or enforce string keys in the doc/spec for this top-level infer.
    # For now, assume API.infer's validation handles it or user provides string keys.
    # with {:ok, inputs} <- encode_inputs(input_vstream_infos, inputs),
    #      {:ok, results} <- API.infer(pipeline, inputs) do
    #   output_parser.parse(results, output_parser_opts)
    # end
    with {:ok, results} <- API.infer(pipeline, inputs) do
      output_parser.parse(results, output_parser_opts)
    end
  end

  # defp encode_inputs(input_vstream_infos, inputs) do
  #   if length(input_vstream_infos) != map_size(inputs) do
  #     {:error, "Number of input vstream infos does not match number of inputs"}
  #   else
  #     result =
  #       Enum.reduce_while(input_vstream_infos, {[], 0}, fn vstream_info, {acc, index} ->
  #         key = vstream_info.name
  #         input = Map.get(inputs, key)

  #         shape_size = vstream_info.shape |> Map.values() |> Enum.product()

  #         cond do
  #           is_nil(input) ->
  #             {:halt, {:error, "Input #{key} not found in inputs"}}

  #           shape_size != Nx.size(input) ->
  #             {:halt,
  #              {:error,
  #               "Size for input #{index} does not match vstream info shape size. Expected #{inspect(vstream_info.shape)}, got #{inspect(Nx.shape(input))}"}}

  #           true ->
  #             {:cont, {[{key, Nx.to_binary(input)} | acc], index + 1}}
  #         end
  #       end)

  #     case result do
  #       {:error, reason} ->
  #         {:error, reason}

  #       {inputs, _} ->
  #         {:ok, Map.new(inputs)}
  #     end
  #   end
  # end
end
