defmodule ExNVR.PipelineStarterTest do
  @moduledoc false

  use ExUnit.Case, async: true

  @moduletag capture_log: true

  alias ExNVR.PipelineStarter

  setup do
    # Trap exits so the `:normal` stop of the (linked) starter is delivered
    # deterministically, regardless of how fast it finishes.
    Process.flag(:trap_exit, true)
    :ok
  end

  defp start_starter(start_fun, opts \\ []) do
    PipelineStarter.start_link(
      [name: nil, start_fun: start_fun, initial_backoff: 5, max_backoff: 50] ++ opts
    )
  end

  test "stops normally without retrying when the start function succeeds" do
    test_pid = self()
    start_fun = fn -> send(test_pid, :started) end

    {:ok, pid} = start_starter(start_fun)

    assert_receive :started
    assert_receive {:EXIT, ^pid, :normal}
    refute_received :started
  end

  test "retries with backoff and eventually stops once the start function succeeds" do
    test_pid = self()
    counter = :counters.new(1, [])

    start_fun = fn ->
      attempt = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      send(test_pid, {:attempt, attempt})
      # Fail the first two attempts (transient DB lock / storage hiccup at boot).
      if attempt < 2, do: raise("boom")
    end

    {:ok, pid} = start_starter(start_fun)

    assert_receive {:attempt, 0}
    assert_receive {:attempt, 1}
    assert_receive {:attempt, 2}
    assert_receive {:EXIT, ^pid, :normal}
    refute_received {:attempt, 3}
  end

  test "keeps retrying without crashing when the start function throws" do
    test_pid = self()
    counter = :counters.new(1, [])

    start_fun = fn ->
      attempt = :counters.get(counter, 1)
      :counters.add(counter, 1, 1)
      send(test_pid, {:attempt, attempt})
      if attempt < 1, do: throw(:nope)
    end

    {:ok, pid} = start_starter(start_fun)

    assert_receive {:attempt, 0}
    assert_receive {:attempt, 1}
    assert_receive {:EXIT, ^pid, :normal}
  end
end
