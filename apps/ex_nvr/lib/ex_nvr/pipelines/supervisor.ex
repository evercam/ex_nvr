defmodule ExNVR.Pipelines.Supervisor do
  @moduledoc """
  A dynamic supervisor for all the pipelines
  """

  use DynamicSupervisor

  import ExNVR.Utils

  alias ExNVR.Model.Device
  alias ExNVR.Pipeline

  def start_link(_opts) do
    DynamicSupervisor.start_link(strategy: :one_for_one, name: __MODULE__)
  end

  def start_pipeline(%Device{} = device) do
    if ExNVR.Utils.run_main_pipeline?() do
      File.mkdir_p!(recording_dir(device.id))
      File.mkdir_p!(hls_dir(device.id))

      DynamicSupervisor.start_child(__MODULE__, {Pipeline, [device: device]})
    end
  end

  def stop_pipeline(%Device{} = device) do
    if ExNVR.Utils.run_main_pipeline?() do
      DynamicSupervisor.terminate_child(__MODULE__, Pipeline.supervisor(device))
    end
  end

  def restart_pipeline(%Device{} = device) do
    # Making the Pipeline restart mode to transient
    # doesn't work because of a bug in Membrane
    # https://github.com/membraneframework/membrane_core/issues/566
    # we'll terminate the children with `terminate_child` and then restart
    stop_pipeline(device)
    start_pipeline(device)
  end
end
