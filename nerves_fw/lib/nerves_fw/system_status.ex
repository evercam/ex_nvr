defmodule ExNVR.Nerves.SystemStatus do
  @moduledoc """
  Can nerves specific system status information and
  merge them with `ExNVR.SystemStatus`.
  """

  use GenServer

  alias ExNVR.Nerves.Hardware.Power
  alias ExNVR.Nerves.RUT

  def start_link(_options) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_options) do
    Process.send_after(self(), :collect_system_metrics, 0)
    {:ok, nil}
  end

  @impl true
  def handle_info(:collect_system_metrics, state) do
    :ok = ExNVR.SystemStatus.set(:hostname, hostname())
    :ok = ExNVR.SystemStatus.set(:router, rut_data())
    :ok = ExNVR.SystemStatus.set(:netbird, netbird())
    :ok = ExNVR.SystemStatus.set(:nerves, true)
    :ok = ExNVR.SystemStatus.set(:device_model, Nerves.Runtime.KV.get("a.nerves_fw_platform"))

    if data = power_data() do
      :ok = ExNVR.SystemStatus.set(:power, data)
    end

    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 30))
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp hostname() do
    case Nerves.Runtime.KV.get("nerves_evercam_id") do
      "" -> :inet.gethostname() |> elem(1) |> List.to_string()
      evercam_id -> evercam_id
    end
  end

  defp netbird() do
    case ExNVR.Nerves.Netbird.status() do
      {:ok, data} -> data
      _error -> false
    end
  end

  defp rut_data() do
    case RUT.system_information() do
      {:ok, data} -> data
      _error -> nil
    end
  end

  defp power_data() do
    case Process.whereis(Power) do
      pid when is_pid(pid) -> Power.state(false)
      _other -> nil
    end
  end
end
