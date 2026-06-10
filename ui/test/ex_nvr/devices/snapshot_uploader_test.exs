defmodule ExNVR.Devices.SnapshotUploaderTest do
  use ExUnit.Case, async: true

  alias ExNVR.Devices.SnapshotUploader
  alias ExNVR.Model.{Device, Schedule}

  # 2026-06-08 is a Monday ("1"), 2026-06-09 a Tuesday ("2")
  @monday_morning ~U[2026-06-08 09:30:00Z]
  @tuesday_morning ~U[2026-06-09 09:30:00Z]

  defp device(timezone \\ "UTC"), do: %Device{timezone: timezone}

  defp schedule(map), do: Schedule.parse!(map)

  defp full_week_schedule(intervals) do
    Map.new(1..7, fn day -> {Integer.to_string(day), intervals} end)
  end

  describe "scheduled?/3" do
    test "returns true when current time falls within a scheduled interval" do
      schedule = schedule(full_week_schedule(["08:00-17:00"]))

      assert SnapshotUploader.scheduled?(device(), schedule, @monday_morning)
    end

    test "interval bounds are inclusive" do
      schedule = schedule(full_week_schedule(["08:00-17:00"]))

      assert SnapshotUploader.scheduled?(device(), schedule, ~U[2026-06-08 08:00:00Z])
      assert SnapshotUploader.scheduled?(device(), schedule, ~U[2026-06-08 17:00:59Z])
    end

    test "returns false when current time is outside scheduled intervals" do
      schedule = schedule(full_week_schedule(["08:00-17:00"]))

      refute SnapshotUploader.scheduled?(device(), schedule, ~U[2026-06-08 07:59:59Z])
      refute SnapshotUploader.scheduled?(device(), schedule, ~U[2026-06-08 18:00:00Z])
    end

    test "returns false when the current day has an empty schedule" do
      schedule = schedule(%{"1" => ["08:00-17:00"], "2" => []})

      refute SnapshotUploader.scheduled?(device(), schedule, @tuesday_morning)
    end

    test "returns false when the schedule is missing the current day key" do
      # legacy/partial schedule maps may not contain entries for all days
      schedule = schedule(%{"1" => ["08:00-17:00"]})

      refute SnapshotUploader.scheduled?(device(), schedule, @tuesday_morning)
    end

    test "returns false for an empty schedule map" do
      refute SnapshotUploader.scheduled?(device(), %{}, @monday_morning)
    end

    test "evaluates the schedule in the device timezone" do
      # Monday 22:00 UTC is Tuesday 07:00 in Asia/Tokyo (UTC+9)
      utc_now = ~U[2026-06-08 22:00:00Z]
      schedule = schedule(%{"1" => [], "2" => ["06:00-08:00"]})

      assert SnapshotUploader.scheduled?(device("Asia/Tokyo"), schedule, utc_now)
      refute SnapshotUploader.scheduled?(device("UTC"), schedule, utc_now)
    end

    @tag capture_log: true
    test "falls back to UTC when the device timezone cannot be resolved" do
      schedule = schedule(%{"1" => ["08:00-17:00"]})

      assert SnapshotUploader.scheduled?(device("Invalid/Timezone"), schedule, @monday_morning)
      refute SnapshotUploader.scheduled?(device("Invalid/Timezone"), schedule, @tuesday_morning)
    end
  end
end
