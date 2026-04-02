---
name: run
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/model/run.ex
  - ui/lib/ex_nvr/recordings.ex
  - ui/lib/ex_nvr/pipeline/output/storage.ex
relates_to:
  concepts: [device, recording]
  features: [video-recording, playback]
---

## Overview

A **Run** represents a single uninterrupted recording session for a [device](device.md). Think of it as "the camera was connected and recording from time A to time B without interruption." When an RTSP connection drops and reconnects, the previous run is ended and a new one begins.

Runs serve as the primary mechanism for answering "when does footage exist?" Individual [recordings](recording.md) are fine-grained segments (typically 60 seconds each), but users and UI components need a higher-level view — the timeline of continuous availability. Runs provide that view. The REST API endpoint `GET /api/devices/:id/recordings` returns runs (not individual recordings), and the playback timeline component uses runs to show green bars where footage is available.

Runs are created and managed by the storage pipeline (`ExNVR.Pipeline.Output.Storage`), not by user-facing code. Each time a new segment is finalized, the run's `end_date` is extended. When a discontinuity occurs (stream disconnect, codec change, end of stream), the run is marked inactive (`active: false`) and a new run will be created when recording resumes.

## Data model

### `ExNVR.Model.Run` (`ui/lib/ex_nvr/model/run.ex`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | integer (auto) | — | Primary key |
| `start_date` | `:utc_datetime_usec` | — | When the session began |
| `end_date` | `:utc_datetime_usec` | — | When the session ended (extended as segments complete) |
| `active` | `:boolean` | `false` | `true` while the session is still recording |
| `stream` | `Ecto.Enum` | `:high` | `:high` (main stream) or `:low` (sub-stream) |
| `disk_serial` | `:string` | — | Serial number of the physical disk storing the recordings |
| `device_id` | `:binary_id` | — | FK to [device](device.md) |

Recordings reference runs via `run_id`, creating a one-to-many relationship: one run contains many sequential recording segments.

## Business logic

### Run lifecycle

Runs are created and managed entirely by the `ExNVR.Pipeline.Output.Storage` Membrane sink:

1. **Creation**: When the first segment of a new session is finalized (`close_file/2`), a `%Run{}` struct is built with `active: true` and the `disk_serial` resolved from the storage mountpoint via `ExNVR.Disk.list_drives/0`.

2. **Extension**: On each subsequent segment finalization, the run's `end_date` is updated to the segment's end date. The run is upserted via `Recordings.create/4` with `on_conflict: {:replace_all_except, [:start_date]}` — this ensures the start date is immutable once set.

3. **Termination**: When a discontinuity occurs (stream disconnect, codec change, `end_of_stream`), the run is marked `active: false`. The next recording session will create a fresh run.

### Deactivation

`Recordings.deactivate_runs/1` sets `active: false` on all active runs for a device. This is used during device shutdown or pipeline termination to ensure no stale active runs remain.

### Run summary and timeline merging

`Run.summary/1` produces a simplified availability timeline by merging adjacent runs that are separated by gaps smaller than a configurable threshold (in seconds). The query uses SQLite window functions:

1. `lag(end_date)` to find the previous run's end date within each `(device_id, disk_serial)` partition
2. `julianday` arithmetic to detect gaps exceeding the threshold
3. Cumulative `sum` of "new group" flags to assign group IDs
4. `min(start_date)` / `max(end_date)` aggregation per group

The result is grouped by `device_id` and `disk_serial`, providing per-disk timelines. This is used by `Recordings.runs_summary/1` which the UI consumes for timeline rendering.

### Clock correction

When NTP sync causes a clock jump, `Recordings.correct_run_dates/3` adjusts the run's `start_date` and `end_date` by a given microsecond offset, along with all associated recording timestamps and filenames.

## API surface

Runs are exposed through the recordings context rather than having their own controller:

- `Recordings.list_runs/2` — Filters runs by `device_id` and `start_date`, ordered by `device_id` then `start_date`
- `Recordings.runs_summary/1` — Returns merged timeline data grouped by device and disk
- `Recordings.deactivate_runs/1` — Bulk deactivates all active runs for a device

The REST API at `GET /api/devices/:device_id/recordings` returns runs as `[{start_date, end_date, active}]`, providing the availability timeline for a device.

## Related concepts

- [device](device.md) — The video source that owns runs
- [recording](recording.md) — Individual MP4 segments that belong to a run
