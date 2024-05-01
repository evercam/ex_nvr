defmodule ExNVR.DeviceSupervisor do
  @moduledoc false

  use Supervisor

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
    params = [device: device]

    children = [
      {ExNVR.DiskMonitor, params},
      {Main, params},
      {ExNVR.BIF.GeneratorServer, params},
      {ExNVR.Devices.SnapshotUploader, params}
    ]

    children =
      if device.settings.enable_lpr && Device.http_url(device) do
        children ++ [{ExNVR.Devices.LPREventPuller, params}]
      else
        children
      end

    children =
      case :os.type() do
        {:unix, _name} -> children ++ [{ExNVR.UnixSocketServer, params}]
        _other -> children
      end

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 10_000)
  end

  @spec stop(Device.t()) :: :ok
  def stop(device) do
    device
    |> supervisor_name()
    |> Process.whereis()
    |> case do
      nil ->
        :ok

      pid ->
        # We terminate the pipeline first to allow it to do cleanup.
        # Without this, the pipeline is killed directly.
        terminate_pipeline(device)
        Supervisor.stop(pid)
    end
  end

  @spec restart(Device.t()) :: :ok
  def restart(device) do
    stop(device)
    start(device)
  end

  defp terminate_pipeline(device) do
    device
    |> ExNVR.Utils.pipeline_name()
    |> Process.whereis()
    |> Membrane.Pipeline.terminate(force?: true, timeout: :timer.seconds(10))
  end

  defp supervisor_name(device), do: :"#{device.id}"
end
