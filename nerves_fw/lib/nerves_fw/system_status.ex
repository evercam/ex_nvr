defmodule ExNVR.Nerves.SystemStatus do
  @moduledoc """
  Can nerves specific system status information and
  merge them with `ExNVR.SystemStatus`.
  """

  use GenServer

  alias ExNVR.Nerves.Monitoring.UPS
  alias ExNVR.Nerves.{Netbird, RUT}
  alias Nerves.Runtime

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
    :ok = ExNVR.SystemStatus.set(:local_ip, local_ip())
    :ok = ExNVR.SystemStatus.set(:router, rut_data())
    :ok = ExNVR.SystemStatus.set(:netbird, netbird())
    :ok = ExNVR.SystemStatus.set(:nerves, true)
    :ok = ExNVR.SystemStatus.set(:device_model, Runtime.KV.get("a.nerves_fw_platform"))
    :ok = ExNVR.SystemStatus.set(:ups, ups_data())

    Process.send_after(self(), :collect_system_metrics, to_timeout(second: 30))
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp hostname do
    case Nerves.Runtime.KV.get("nerves_evercam_id") do
      "" -> :inet.gethostname() |> elem(1) |> List.to_string()
      evercam_id -> evercam_id
    end
  end

  def local_ip do
    VintageNet.get(["interface", "eth0", "addresses"])
    |> Enum.find_value(nil, fn
      %{family: :inet, address: addr} ->
        addr
        |> :inet.ntoa()
        |> to_string()

      _ ->
        nil
    end)
  end

  defp netbird do
    case Netbird.status() do
      {:ok, data} -> data
      _error -> false
    end
  end

  defp rut_data do
    case RUT.system_information() do
      {:ok, data} -> data
      _error -> nil
    end
  end

  defp ups_data do
    case Process.whereis(UPS) do
      pid when is_pid(pid) -> UPS.state(pid)
      _other -> nil
    end
  end
end
