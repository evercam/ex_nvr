defmodule ExNVR.SystemStatus.RegistryTest do
  @moduledoc false

  use ExNVR.DataCase

  alias ExNVR.Hardware.Victron
  alias ExNVR.SystemStatus

  test "test system status" do
    assert {:ok, %{data: %{}} = state} = SystemStatus.init(nil)

    assert_receive :collect_system_metrics, 500

    assert {:noreply, %{data: data}} = SystemStatus.handle_info(:collect_system_metrics, state)

    assert %{
             memory: memory,
             cpu: %{load: load, num_cores: num_cores, per_core: per_core, usage: usage}
           } = data

    assert is_map(memory)
    assert [load1, load5, load15] = load
    assert is_number(load1)
    assert is_number(load5)
    assert is_number(load15)
    assert is_number(num_cores)
    assert is_list(per_core)
    assert is_number(usage)

    assert :ok = SystemStatus.terminate(:normal, state)
  end

  test "System status gen_server" do
    assert {:ok, pid} = SystemStatus.start_link(name: __MODULE__)
    assert %{} = SystemStatus.get_all(__MODULE__)

    victron_mppt = %Victron{v: 25_000, i: 1_600}
    SystemStatus.set(__MODULE__, :solar_charger, victron_mppt)

    assert %{solar_charger: ^victron_mppt} = SystemStatus.get_all(__MODULE__)

    assert :ok = SystemStatus.set(__MODULE__, :key, :value)
    assert %{key: :value} = SystemStatus.get_all(__MODULE__)

    assert %{num_cores: _num_cores, load: _load} = SystemStatus.get(:cpu, __MODULE__)

    assert :ok = GenServer.stop(pid)
    refute Process.alive?(pid)
  end

  describe "PubSub broadcasts" do
    test "subscribe/0 receives a broadcast after set/3" do
      assert {:ok, pid} = SystemStatus.start_link(name: :"#{__MODULE__}.PubSubSet")
      :ok = SystemStatus.subscribe()

      :ok = SystemStatus.set(pid, :hostname, "test-host")

      assert_receive {:system_status, %{hostname: "test-host"}}, 500

      :ok = GenServer.stop(pid)
    end

    test "collection tick broadcasts the latest snapshot" do
      assert {:ok, pid} = SystemStatus.start_link(name: :"#{__MODULE__}.PubSubTick")
      :ok = SystemStatus.subscribe()

      send(pid, :collect_system_metrics)

      assert_receive {:system_status, %{cpu: %{num_cores: cores, per_core: per_core}}}, 500
      assert is_number(cores)
      assert is_list(per_core)

      :ok = GenServer.stop(pid)
    end
  end

  describe "telemetry events" do
    test "set(:solar_charger, _) emits [:ex_nvr, :system, :solar]" do
      assert {:ok, pid} = SystemStatus.start_link(name: :"#{__MODULE__}.Telemetry")

      ref = make_ref()
      parent = self()

      :telemetry.attach(
        "test-solar-#{inspect(ref)}",
        [:ex_nvr, :system, :solar],
        fn _, measurements, metadata, _ ->
          send(parent, {ref, :solar, measurements, metadata})
        end,
        nil
      )

      :ok = SystemStatus.set(pid, :solar_charger, %Victron{v: 24_500, i: 1_200, ppv: 35})

      assert_receive {^ref, :solar, %{voltage_mv: 24_500, current_ma: 1_200, panel_power_w: 35},
                      %{}},
                     500

      :telemetry.detach("test-solar-#{inspect(ref)}")
      :ok = GenServer.stop(pid)
    end
  end
end
