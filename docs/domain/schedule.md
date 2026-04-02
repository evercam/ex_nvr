---
name: schedule
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/model/schedule.ex
  - ui/lib/ex_nvr/pipeline/storage_monitor.ex
  - ui/lib/ex_nvr/model/device/storage_config.ex
  - ui/lib/ex_nvr/model/device/snapshot_config.ex
  - ui/lib/ex_nvr/devices/snapshot_uploader.ex
relates_to:
  concepts: [device]
  features: [video-recording, device-management, snapshot-upload]
---

## Overview

A **Schedule** is a weekly time-slot map that controls when an activity is allowed to run. It answers the question "is now within an allowed time window?" for two recurring operations in ExNVR: **recording** and **snapshot uploading**.

Rather than simple on/off toggles, schedules give operators fine-grained control over when a [device](device.md) records video or uploads snapshots. A parking garage camera might record only during business hours (Mon–Fri 08:00–18:00). A construction site camera might upload snapshots every 30 seconds during the day but stop at night to save bandwidth.

Schedules are not a standalone entity with their own database table — they are embedded as a `:map` field inside two device config schemas:

1. **`Device.StorageConfig.schedule`** — Controls when the recording pipeline writes video segments to disk. The `ExNVR.Pipeline.StorageMonitor` GenServer polls this schedule every 5 seconds and sends `{:storage_monitor, :record?, boolean}` messages to the Membrane pipeline to start or stop recording.

2. **`Device.SnapshotConfig.schedule`** — Controls when the `ExNVR.Devices.SnapshotUploader` captures and uploads snapshots. The uploader checks the schedule before each upload cycle.

When no schedule is configured (`nil`), the activity is always allowed — schedules are opt-in restrictions, not opt-in permissions.

## Data model

### Schedule format

A schedule is a map with string keys `"1"` through `"7"` representing days of the week (Monday=1 through Sunday=7, following ISO 8601 / `Date.day_of_week/1`). Each day maps to a list of time interval strings in `"HH:MM-HH:MM"` format:

```elixir
%{
  "1" => ["08:00-12:00", "13:00-18:00"],   # Monday: two windows
  "2" => ["08:00-18:00"],                   # Tuesday: one window
  "3" => [],                                # Wednesday: disabled
  "4" => ["00:00-23:59"],                   # Thursday: all day
  "5" => ["08:00-12:00"],                   # Friday: morning only
  "6" => [],                                # Saturday: disabled
  "7" => []                                 # Sunday: disabled
}
```

**Parsing**: `Schedule.parse/1` converts the string-based format to structured maps with `Time` structs. Start times get `:00` seconds appended, end times get `:59` seconds — so `"08:00-12:00"` becomes `%{start_time: ~T[08:00:00], end_time: ~T[12:00:59]}`. This ensures the full minute is covered.

## Business logic

### `ExNVR.Model.Schedule` (`ui/lib/ex_nvr/model/schedule.ex`)

**`validate/1`** — The main entry point for schedule validation, used by both `StorageConfig` and `SnapshotConfig` changesets. Performs three checks in sequence:

1. **Day validation** — All keys must be in `"1".."7"`. Extra or invalid keys produce `{:error, :invalid_schedule_days}`.
2. **Interval parsing** — Each time interval must be a valid `"HH:MM-HH:MM"` string. Invalid formats produce `{:error, :invalid_time_intervals}`.
3. **Interval logic** — Within each day:
   - End time must be after start time (`{:error, :invalid_time_interval_range}`)
   - Intervals must not overlap when sorted by start time (`{:error, :overlapping_intervals}`)

On success, returns the schedule with intervals sorted within each day. Missing days are backfilled with empty lists.

**`scheduled?/2`** — The runtime check. Given a parsed schedule and a `DateTime`, determines the day of week, truncates to seconds, and checks if the time falls within any interval for that day. Returns `true` if the time is within range (inclusive on both ends), `false` otherwise.

**`parse!/1`** — Strict variant of `parse/1` that raises on invalid schedules. Used by `StorageMonitor.init/1` where the schedule has already been validated at the changeset level.

### Recording schedule — `ExNVR.Pipeline.StorageMonitor`

A GenServer started as a child of the main Membrane pipeline. Monitors two conditions that determine whether recording should be active:

1. **Directory writability** — Checks that the storage directory exists and is writable. If not, polls every 5 seconds until it becomes available.
2. **Schedule** — If a schedule is configured, polls `Schedule.scheduled?/2` every 5 seconds using the device's timezone.

The monitor sends `{:storage_monitor, :record?, boolean}` to the pipeline process. It deduplicates notifications — only sends when the `record?` value actually changes. The pipeline uses this to start/stop writing to the storage sink.

The monitor also supports `pause/1` and `resume/1` calls, used by the pipeline to temporarily suspend recording (e.g. when the disk is full and the `DiskMonitor` triggers cleanup).

Key logic in `record?/1`:
- `recording_mode: :never` → always `false`
- No schedule configured → always `true`
- Schedule configured → delegates to `Schedule.scheduled?/2` with the current time in the device's timezone

### Snapshot schedule — `ExNVR.Devices.SnapshotUploader`

The snapshot uploader performs a similar schedule check inline before each upload cycle. The `scheduled?/2` private function in the uploader reads the device's timezone, gets the current day of week, looks up the time intervals for that day, and checks if the current time falls within any interval.

## Related concepts

- [device](device.md) — Schedules are embedded in a device's `storage_config` and `snapshot_config`

## Business rules

- **Schedules are timezone-aware** — Schedule checks use the device's configured `timezone` to convert the current UTC time to local time before comparison. A schedule set to "08:00-18:00" means 8 AM to 6 PM in the device's timezone, not UTC.
- **Nil schedule means always active** — When `storage_config.schedule` or `snapshot_config.schedule` is `nil`, the activity runs without time restrictions.
- **Empty day means disabled** — A day with an empty list `[]` means the activity is completely disabled for that day.
- **Intervals are inclusive** — Both start and end times are inclusive. `"08:00-12:00"` covers 08:00:00 through 12:00:59.
- **No overlapping intervals** — Validation rejects intervals that overlap within the same day. Adjacent intervals (e.g. `"08:00-12:00"` and `"12:01-18:00"`) are allowed.
- **Intervals are sorted on validation** — `validate/1` sorts intervals by start time within each day before returning, ensuring consistent storage.
- **5-second polling granularity** — The `StorageMonitor` checks the schedule every 5 seconds, meaning there can be up to a 5-second delay between a schedule boundary and the actual start/stop of recording.
