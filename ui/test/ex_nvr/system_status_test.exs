defmodule ExNVR.SystemStatus.RegistryTest do
  @moduledoc false

  use ExNVR.DataCase

  alias ExNVR.Hardware.SolarCharger.VictronMPPT
  alias ExNVR.SystemStatus

  test "test system status" do
    assert {:ok, %{data: %{}} = state} = SystemStatus.init(nil)

    assert_receive :collect_system_metrics, 500

    assert {:reply, :ok, state} = SystemStatus.handle_call({:register, :solar_charger}, nil, state)
    assert {:noreply, %{data: data}} = SystemStatus.handle_info(:collect_system_metrics, state)

    assert %{
             memory: memory,
             cpu: %{load: load, num_cores: num_cores}
           } = data

    assert is_map(memory)
    assert [load1, load5, load15] = load
    assert is_number(load1)
    assert is_number(load5)
    assert is_number(load15)
    assert is_number(num_cores)

    assert :ok = SystemStatus.terminate(:normal, state)
  end

  test "System status gen_server" do
    assert {:ok, pid} = SystemStatus.start_link(name: __MODULE__)
    assert %{} = SystemStatus.get(__MODULE__)

    SystemStatus.register(__MODULE__, :solar_charger)

    victron_mppt = %VictronMPPT{v: 25_000, i: 1_600}
    :telemetry.execute([:system, :status, :solar_charger], %{value: victron_mppt})

    assert %{solar_charger: ^victron_mppt} = SystemStatus.get(__MODULE__)

    assert :ok = SystemStatus.set(__MODULE__, :key, :value)
    assert %{key: :value} = SystemStatus.get(__MODULE__)

    assert :ok = GenServer.stop(pid)
    refute Process.alive?(pid)
  end
end
