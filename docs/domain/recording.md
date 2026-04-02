---
name: recording
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/model/recording.ex
  - ui/lib/ex_nvr/model/run.ex
  - ui/lib/ex_nvr/recordings.ex
  - ui/lib/ex_nvr/recordings/**/*.ex
  - ui/lib/ex_nvr/elements/recording.ex
  - ui/lib/ex_nvr_web/controllers/api/recording_controller.ex
  - ui/lib/ex_nvr_web/live/recordings_list_live.ex
  - ui/lib/ex_nvr_web/live/device_tabs/recordings_list_tab.ex
  - ui/lib/ex_nvr/pipeline/output/storage.ex
  - ui/lib/ex_nvr/pipeline/output/storage/**/*.ex
relates_to:
  concepts: [device, run, schedule]
  features: [video-recording, playback, remote-storage-sync, bif-thumbnails]
---

## Overview

A **Recording** is a single MP4 video segment stored on disk, representing a contiguous chunk of footage from a [device](device.md). Recordings are the fundamental unit of stored video in ExNVR — they are what gets queried for playback, downloaded as footage clips, browsed in the UI, and synced to remote storage.

The recording pipeline continuously writes incoming RTSP frames into fixed-duration segments (default 60 seconds). Each segment is finalized at the next keyframe after the target duration elapses, so actual segment lengths may be slightly longer. When a segment is complete, the `ExNVR.Pipeline.Output.Storage` Membrane sink creates a `Recording` row in the database and closes the MP4 file.

Recordings are grouped into **[Runs](run.md)** — a run represents a single uninterrupted recording session (e.g. one RTSP connection from start to disconnect). When the stream breaks and reconnects, a new run is created. Runs provide the "availability timeline" that the UI and API use to show when footage exists.

Each recording exists in one of two stream qualities: `:high` (main stream) or `:low` (sub-stream). Both are stored independently and can be queried separately.

The system manages disk usage by deleting the oldest recordings when the drive fills up (see `delete_oldest_recordings/2`). It also handles NTP clock jumps by adjusting recording timestamps and renaming files (`correct_run_dates/3`).

## Data model

### `ExNVR.Model.Recording` (`ui/lib/ex_nvr/model/recording.ex`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | integer (auto) | Primary key |
| `start_date` | `:utc_datetime_usec` | When the segment begins |
| `end_date` | `:utc_datetime_usec` | When the segment ends |
| `filename` | `:string` | Basename of the MP4 file (e.g. `1711929600000000.mp4`) |
| `stream` | `Ecto.Enum` | `:high` or `:low` (default `:high`) |
| `device_id` | `:binary_id` | FK to [device](device.md) |
| `run_id` | `:integer` | FK to [run](run.md) |

**Flop integration**: The schema derives `Flop.Schema` with filterable fields (`start_date`, `end_date`, `device_id`), sortable fields (including `device_name` via join), page-based pagination (default limit 20, max 30), and a default descending sort by `start_date`.

### File naming and path convention

Recording files are named by their start timestamp as a Unix microsecond value: `{unix_microseconds}.mp4`. The full path is:

```
{storage_address}/ex_nvr/{device_id}/{hi_quality|lo_quality}/{YYYY}/{MM}/{DD}/{unix_us}.mp4
```

For example: `/data/ex_nvr/abc-123/hi_quality/2024/04/01/1711929600000000.mp4`

The path is constructed by `Recordings.recording_path/3` using `ExNVR.Utils.date_components/1` to split the start date into year/month/day subdirectories.

### `ExNVR.Model.Run` (`ui/lib/ex_nvr/model/run.ex`)

| Field | Type | Notes |
|-------|------|-------|
| `id` | integer (auto) | Primary key |
| `start_date` | `:utc_datetime_usec` | When the session started |
| `end_date` | `:utc_datetime_usec` | When the session ended (updated as segments complete) |
| `active` | `:boolean` | `true` while the session is still recording |
| `stream` | `Ecto.Enum` | `:high` or `:low` |
| `disk_serial` | `:string` | Serial number of the disk where recordings are stored |
| `device_id` | `:binary_id` | FK to device |

Runs have a `summary/1` query that merges adjacent runs with gaps smaller than a threshold (in seconds), using window functions to group them. This produces a simplified timeline for the UI, partitioned by `device_id` and `disk_serial`.

## API surface

### REST API

All recording routes are scoped under `/api/` and require authentication via `ExNVRWeb.Plug.Device`.

| Method | Path | Action | Description |
|--------|------|--------|-------------|
| `GET` | `/api/recordings/chunks` | `RecordingController.chunks` | Paginated list of recording segments across all devices (Flop) |
| `GET` | `/api/devices/:device_id/recordings` | `RecordingController.index` | List runs (availability timeline) for a device, optionally filtered by `start_date` and `stream` |
| `GET` | `/api/devices/:device_id/recordings/:recording_id/blob` | `RecordingController.blob` | Download the raw MP4 file for a specific recording |
| `GET` | `/api/devices/:device_id/snapshot` | `DeviceStreamingController.snapshot` | Extract a JPEG frame from a recorded segment at a given `time` |
| `GET` | `/api/devices/:device_id/footage` | `DeviceStreamingController.footage` | Assemble and download a footage clip spanning multiple recordings |

The `index` endpoint returns runs (not individual recordings) as `[{start_date, end_date, active}]` — this is what timeline components use to show recording availability.

The `chunks` endpoint returns paginated recordings with metadata (`current_page`, `page_size`, `total_count`, `total_pages`).

### LiveView

| Path | Module | Notes |
|------|--------|-------|
| `/recordings` | `RecordingListLive` | Global recordings list with filtering and pagination |
| `/devices/:id/details?tab=recordings` | `DeviceTabs.RecordingsListTab` | Device-scoped recordings tab with Flop table, date filters, details popover, preview modal, and download links |

## Business logic

### `ExNVR.Recordings` context (`ui/lib/ex_nvr/recordings.ex`)

**Creating recordings** (`create/4`):
1. Optionally copies the MP4 file from a temporary path to the final recording directory
2. Upserts the run (using `on_conflict: {:replace_all_except, [:start_date]}` — the run's start date is immutable once set)
3. Inserts the recording with the filename derived from the start date
4. Broadcasts `{:new, nil}` on the `"recordings"` PubSub topic

**Querying recordings**:
- `list/2` — Flop-powered paginated listing with device join, filtered by stream type
- `get_recordings_between/5` — Returns recordings overlapping a time range (limit defaults to 50)
- `exists?/3` — Checks if any recording exists at a specific point in time for a device/stream
- `details/2` — Reads the MP4 file to return file size, duration, and track details

**Snapshot extraction** (`snapshot/4`):
1. Opens the MP4 file with `ExMP4.Reader`
2. Seeks to the requested timestamp within the recording
3. Supports two methods: `:before` (nearest preceding keyframe) and `:precise` (decode up to exact frame)
4. Decodes the video frame and encodes it as JPEG via `AV.VideoProcessor.encode_to_jpeg/1`

**Footage download** (`download_footage/6`):
Delegates to `VideoAssembler.assemble/6` which uses the `Concatenater` to stream samples from multiple recording files into a single output MP4. Supports both `end_date` and `duration` bounds (max 2 hours / 7200 seconds).

**Deletion** (`delete_oldest_recordings/2`):
1. Finds the N oldest high-quality recordings for the device
2. Finds all low-quality recordings that end before the last high-quality recording's end date
3. Deletes the recording rows and the MP4 files in a multi-transaction
4. Cleans up orphaned runs (runs whose end date is before the new oldest recording)
5. Adjusts the oldest remaining run's start date to match the oldest surviving recording
6. Broadcasts `{:delete, nil}` and emits telemetry `[:ex_nvr, :recording, :delete]`

**Clock correction** (`correct_run_dates/3`):
When an NTP sync causes a clock jump, this function adjusts all recording timestamps and filenames in a run by a given duration offset, and renames the physical files on disk to match.

### `ExNVR.Recordings.Concatenater` (`ui/lib/ex_nvr/recordings/concatenater.ex`)

Provides a virtual view over multiple recording files as if they were one continuous stream. Used by both the `ExNVR.Elements.Recording` Membrane source element (for HLS playback) and the `VideoAssembler` (for footage downloads).

Key behaviors:
- Opens recording files sequentially, transparently transitioning between segments
- Handles seeking within the first recording when the start date falls mid-segment
- Normalizes timestamps across files using a fixed video timescale of 90,000
- Converts MP4 samples to Annex B format via `BitStreamFilter.MP4ToAnnexb` (configurable)
- Detects codec changes between consecutive recordings and signals `:codec_changed`

### `ExNVR.Recordings.VideoAssembler` (`ui/lib/ex_nvr/recordings/video_assembler.ex`)

Assembles multiple recording segments into a single MP4 file using `Concatenater` and `ExMP4.Writer`. Stops when either the duration limit or end date is reached.

## System integration

### Storage pipeline (`ExNVR.Pipeline.Output.Storage`)

A Membrane `Sink` element that receives H.264/H.265 access units and writes them to MP4 segments:

- **Segment splitting**: When the current segment exceeds `target_segment_duration` (default 60s) and a keyframe arrives, the current file is finalized and a new one started
- **Timestamp correction**: Optional `correct_timestamp` flag adjusts segment end dates toward the wall clock, clamped to ±30ms. Drifts exceeding 30 seconds are treated as discontinuities
- **First segment handling**: The first segment's start date is adjusted to account for camera buffering, and the file is renamed accordingly
- **Run management**: Creates a new `Run` struct when recording starts or after a discontinuity. The run tracks `disk_serial` (resolved from the storage mountpoint). Runs are marked `active: false` on discontinuity
- **Discontinuity handling**: Stream disconnections, codec changes, and end-of-stream events all trigger discontinuity handling — the current segment is finalized and the run is ended
- **Telemetry**: Emits `[:ex_nvr, :recordings, :stop]` with duration and size metrics per segment

### Recording source element (`ExNVR.Elements.Recording`)

A Membrane `Source` that reads from stored recordings for playback pipelines. Wraps the `Concatenater` and produces H.264/H.265 buffers with proper timestamps. Supports bounded playback via `end_date` and/or `duration` options.

### PubSub

- `"recordings"` topic — broadcasts `{:new, nil}` on creation and `{:delete, nil}` on deletion. Subscribers can use `Recordings.subscribe_to_recording_events/0`.

## Storage

### Database

SQLite table `recordings` with fields `id`, `start_date`, `end_date`, `filename`, `stream`, `device_id`, `run_id`.

SQLite table `runs` with fields `id`, `start_date`, `end_date`, `active`, `stream`, `disk_serial`, `device_id`.

The `Run.summary/1` query uses SQLite window functions (`lag`, `sum` over partitioned windows with `julianday` arithmetic) to merge adjacent runs that are closer than a configurable gap threshold.

### File system

MP4 files are stored in a date-partitioned directory tree under the device's recording directory. Files use `fast_start: true` (moov atom at the beginning) for efficient random access. Each segment contains a single video track with parameter sets (SPS/PPS for H.264, VPS/SPS/PPS for H.265) stored in the track's `priv_data`.

## Related concepts

- [device](device.md) — The video source that owns recordings
- [run](run.md) — Groups contiguous recordings into sessions
- [schedule](schedule.md) — Controls when recording is active

## Business rules

- **Filename is the timestamp**: Recording filenames are always `{unix_microseconds}.mp4`, derived from the start date. This means renaming/correcting timestamps requires physically renaming files on disk.
- **Run start date is immutable**: The `on_conflict` clause in `create/4` uses `{:replace_all_except, [:start_date]}`, ensuring a run's start date is set once and never overwritten by subsequent segment upserts.
- **Disk serial tracking**: Each run records the serial number of the physical disk where recordings are stored, enabling per-disk timeline views (via `Run.summary/1` partitioned by `disk_serial`).
- **Oldest-first deletion**: When disk space runs low, the system deletes the oldest high-quality recordings first, then deletes any low-quality recordings that fall within the same time range.
- **Codec continuity**: The `Concatenater` detects if consecutive recordings use different codecs (e.g. H.264 vs H.265) and signals an error rather than producing corrupted output.
- **Segment duration is approximate**: Segments target 60 seconds but always end on a keyframe boundary, so actual duration may be slightly longer.
