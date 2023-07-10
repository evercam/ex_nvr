defmodule ExNVR.Pipelines.Supervisor do
  @moduledoc """
  A dynamic supervisor for all the pipelines
  """

  import ExNVR.Utils

  alias ExNVR.Model.Device
  alias ExNVR.{Devices, Pipelines}

  def start_pipeline(%Device{} = device) do
    if ExNVR.Utils.run_main_pipeline?() do
      File.mkdir_p!(recording_dir(device.id))
      File.mkdir_p!(hls_dir(device.id))

      children = [
        {Devices.Room, [device: device, name: room_name(device)]},
        {Pipelines.Main, [device: device, rtc_engine: room_name(device)]}
      ]

      options = [strategy: :one_for_one, name: supervisor_name(device)]

      DynamicSupervisor.start_child(
        ExNVR.PipelineSupervisor,
        %{
          id: Supervisor,
          start: {Supervisor, :start_link, [children, options]}
        }
      )
    end
  end

  def stop_pipeline(%Device{} = device) do
    if ExNVR.Utils.run_main_pipeline?() do
      DynamicSupervisor.terminate_child(
        ExNVR.PipelineSupervisor,
        supervisor_name(device)
      )
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

  def room_pid(%Device{} = device), do: Process.whereis(room_name(device))

  defp supervisor_name(%Device{id: id}), do: :"supervisor_#{id}"

  defp room_name(%Device{id: id}), do: :"room_#{id}"
end
