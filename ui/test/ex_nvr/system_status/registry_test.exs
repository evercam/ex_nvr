defmodule ExNVR.SystemStatus.RegistryTest do
  @moduledoc false

  use ExUnit.Case

  alias ExNVR.Hardware.SolarCharger.VictronMPPT
  alias ExNVR.SystemStatus.{Registry, State}

  test "test registry" do
    assert {:ok, %{timer: timer_ref, data: %State{}} = state} = Registry.init(interval: 100)
    assert {:interval, ref} = timer_ref
    assert is_reference(ref)

    assert_receive :collect_metrics, 500

    victron_mppt = %VictronMPPT{v: 25_000, i: 1_600}

    assert {:noreply, %{data: %State{solar_charger: ^victron_mppt}} = state} =
             Registry.handle_info({:solar_charger, victron_mppt}, state)

    assert {:noreply, %{data: data}} = Registry.handle_info(:collect_metrics, state)

    assert %State{
             memory: memory,
             cpu: %{load_avg: load, num_cores: num_cores},
             solar_charger: ^victron_mppt
           } = data

    assert is_map(memory)
    assert {load1, load5, load15} = load
    assert is_number(load1)
    assert is_number(load5)
    assert is_number(load15)
    assert is_number(num_cores)

    assert :ok = Registry.terminate(:normal, state)
  end

  test "registry gen_server" do
    assert {:ok, pid} = Registry.start_link(name: __MODULE__)
    assert %State{} = Registry.get_state(pid)
    assert :ok = GenServer.stop(pid)
    refute Process.alive?(pid)
  end
end
