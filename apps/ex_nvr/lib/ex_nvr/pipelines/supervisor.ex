defmodule ExNVR.Pipelines.Supervisor do
  @moduledoc """
  A dynamic supervisor for all the pipelines
  """

  use DynamicSupervisor

  alias ExNVR.Pipeline

  def start_link(_opts) do
    DynamicSupervisor.start_link(strategy: :one_for_one, name: __MODULE__)
  end

  def start_pipeline(options) do
    DynamicSupervisor.start_child(__MODULE__, {Pipeline, options})
  end
end
