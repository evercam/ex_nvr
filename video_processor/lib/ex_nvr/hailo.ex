defmodule ExNVR.AV.Hailo do
  @moduledoc """
  High-level interface for Hailo model loading and inference.
  """

  alias ExNVR.AV.Hailo.API
  alias ExNVR.AV.Hailo.Model
  alias ExNVR.AV.Hailo.NIF

  @spec available?() :: boolean()
  def available?, do: NIF.loaded?()

  @spec load(Path.t()) :: {:ok, Model.t()} | {:error, term()}
  def load(hef_path) when is_binary(hef_path) do
    with {:ok, vdevice} <- API.create_vdevice(),
         {:ok, network_group} <- API.configure_network_group(vdevice, hef_path),
         {:ok, pipeline} <- API.create_pipeline(network_group) do
      {:ok, %Model{pipeline: pipeline, name: Path.basename(hef_path)}}
    end
  end

  @spec infer(Model.t(), map(), module(), keyword()) :: {:ok, term()} | {:error, term()}
  def infer(%Model{pipeline: %API.Pipeline{} = pipeline}, inputs, output_parser, output_parser_opts \\ [])
      when is_map(inputs) and is_atom(output_parser) do
    with {:ok, outputs} <- API.infer(pipeline, inputs) do
      output_parser.parse(outputs, output_parser_opts)
    end
  end
end
