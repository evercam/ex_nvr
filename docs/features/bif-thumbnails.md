---
name: bif-thumbnails
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/bif/generator_server.ex
  - ui/lib/ex_nvr/bif/writer.ex
  - ui/lib/ex_nvr/bif/index.ex
  - ui/lib/ex_nvr/pipeline/output/thumbnailer.ex
relates_to:
  concepts: [recording, device]
  features: [video-recording, playback]
---

## Overview

**BIF thumbnails** provide video scrubbing preview images — the small thumbnails users see when hovering over a [playback](playback.md) timeline. BIF (Base Index Frames) is a file format originally developed by Roku that bundles many small JPEG thumbnails into a single binary file with a timestamp index, enabling efficient seek-based thumbnail retrieval without individual HTTP requests per frame.

The feature works in two stages:

1. **Thumbnail capture** — The `Output.Thumbnailer` Membrane sink, connected to the sub-stream's tee in the [recording pipeline](video-recording.md), decodes one keyframe every 10 seconds and saves it as a 320px-wide JPEG in the device's `thumbnails/bif/` directory.

2. **BIF file generation** — The `ExNVR.BIF.GeneratorServer` GenServer (part of the per-device supervision tree) runs hourly, collects all JPEG thumbnails from the previous hour(s), bundles them into a BIF file, and deletes the source JPEGs.

The resulting BIF files are served via `GET /api/devices/:id/bif/:hour` with aggressive caching (`immutable, max-age=1year`), since completed hours never change.

## How it works

### Thumbnail capture (pipeline)

The `Output.Thumbnailer` is a Membrane `Sink` that receives H.264/H.265 access units from the sub-stream:

1. Only processes keyframes (non-keyframes are discarded)
2. Checks if at least `interval` seconds (default 10) have elapsed since the last thumbnail
3. Decodes the keyframe using `ExNVR.AV.Decoder` at a target width of 320px (height computed proportionally)
4. Encodes the decoded frame as JPEG via `VideoProcessor.encode_to_jpeg/1`
5. Saves to `{bif_thumbnails_dir}/{unix_timestamp}.jpg`

The thumbnailer only starts when `device.settings.generate_bif` is `true` and the device has a storage address configured.

### BIF file generation (hourly)

The `GeneratorServer` runs on a self-scheduling timer aligned to hour boundaries:

1. On each tick, scans the `thumbnails/bif/` directory for `*.jpg` files
2. Groups files by their hour (truncates Unix timestamp to hour boundary)
3. Filters out the current hour (only processes completed hours)
4. For each completed hour:
   - Sorts the JPEG files chronologically
   - Creates a BIF file using `BIF.Writer` — each image is indexed by its second-within-the-hour (0–3599)
   - Copies the first image to `thumbnails/{hour}.jpg` as an hour-level preview thumbnail
   - Deletes all source JPEG files
5. Schedules next tick for 5 seconds after the next hour boundary

### BIF file format

The `BIF.Writer` produces files with this structure:

```
[8 bytes] Magic number: 0x894249460D0A1A0A
[4 bytes] Version: 0
[4 bytes] Image count (little-endian)
[4 bytes] Reserved (0)
[44 bytes] Reserved (0)
--- Index entries (8 bytes each) ---
[4 bytes] Timestamp in seconds (little-endian)
[4 bytes] Absolute byte offset of image data (little-endian)
... repeated for each image ...
[4 bytes] 0xFFFFFFFF (sentinel)
[4 bytes] Offset past last image
--- Image data ---
[variable] Concatenated JPEG data
```

The writer uses a two-pass approach: image data is written to a `.tmp` file first, then the header + index is prepended by writing to the final file and copying the temp data after it.

## Architecture

### Pipeline integration

```
sub_stream Tee → Output.Thumbnailer → {bif_thumbnails_dir}/*.jpg
                                             ↓
                              GeneratorServer (hourly)
                                             ↓
                                    {bif_dir}/YYYYMMDDHH.bif
```

The thumbnailer is conditionally added to the sub-stream pipeline in `build_sub_stream_bif_spec/1` when both `generate_bif` setting and storage address are present.

### File system layout

```
{storage_address}/ex_nvr/{device_id}/
├── bif/                    # BIF files (YYYYMMDDHH.bif)
└── thumbnails/
    ├── bif/                # Source JPEG thumbnails (transient)
    └── {hour}.jpg          # Hour-level preview thumbnails
```

### Serving BIF files

`GET /api/devices/:id/bif/:hour` (`DeviceStreamingController.bif/2`):
- Takes an `hour` parameter as a UTC datetime
- Looks up the BIF file at `{bif_dir}/{YYYYMMDDHH}.bif`
- Serves with `Cache-Control: private, immutable, max-age=31536000` (1 year) — completed hours are immutable
- Returns 404 if the file doesn't exist (e.g., recording wasn't active during that hour)

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `generate_bif` | `device.settings` | `true` | Enables thumbnail capture + BIF generation |
| `interval` | `Thumbnailer` option | 10 | Seconds between thumbnail captures |
| `thumbnail_width` | `Thumbnailer` option | 320 | Width of generated thumbnails (height proportional) |
| Generation frequency | `GeneratorServer` | Hourly | Runs ~5s after each hour boundary |
