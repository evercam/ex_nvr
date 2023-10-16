defmodule ExNVR.DeviceSupervisor do
  @moduledoc false

  use Supervisor

  import ExNVR.Utils

  alias ExNVR.Model.Device
  alias ExNVR.Pipelines.Main

  @spec start(Device.t()) :: :ok
  def start(device) do
    if ExNVR.Utils.run_main_pipeline?() do
      spec = %{
        id: __MODULE__,
        start: {Supervisor, :start_link, [__MODULE__, device, [name: supervisor_name(device)]]},
        restart: :transient
      }

      DynamicSupervisor.start_child(ExNVR.PipelineSupervisor, spec)
    end

    :ok
  end

  @impl true
  def init(device) do
    File.mkdir_p!(recording_dir(device.id))
    File.mkdir_p!(hls_dir(device.id))
    File.mkdir_p!(bif_dir(device.id))

    params = [device: device]

    children = [
      {Main, params},
      {ExNVR.BifGeneratorServer, params}
    ]

    children =
      case :os.type() do
        {:unix, _name} -> children ++ [{ExNVR.UnixSocketServer, params}]
        _other -> children
      end

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 1_000)
  end

  @spec stop(Device.t()) :: :ok
  def stop(device) do
    device
    |> supervisor_name()
    |> Process.whereis()
    |> case do
      nil -> :ok
      pid -> Supervisor.stop(pid)
    end
  end

  @spec restart(Device.t()) :: :ok
  def restart(device) do
    stop(device)
    start(device)
  end

  defp supervisor_name(device), do: :"#{device.id}"
end
