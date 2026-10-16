defmodule ExNVR.Activity.PrunerTest do
  use ExNVR.DataCase

  import ExNVR.ActivityFixtures

  alias ExNVR.Activity
  alias ExNVR.Activity.Pruner

  test "is not started without a retention" do
    refute Application.get_env(:ex_nvr, :activity_retention_days)
    refute Process.whereis(Pruner)
  end

  test "deletes entries older than the retention" do
    now = DateTime.utc_now()
    old = entry_fixture(time: DateTime.add(now, -8, :day))
    recent = entry_fixture(time: DateTime.add(now, -6, :day))

    pid =
      start_supervised!(
        {Pruner, name: :test_activity_pruner, retention_days: 7, initial_delay: :timer.hours(1)}
      )

    send(pid, :prune)
    :sys.get_state(pid)

    refute Activity.get(old.id)
    assert Activity.get(recent.id)
  end
end
