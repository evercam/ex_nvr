---
description: Glossary index of all documented concepts and features in this repository.
---

# Index

## Concepts

| Name | Summary | Related concepts | Related features |
|------|---------|-----------------|-----------------|
| [device](domain/device.md) | Central entity representing a video source (IP camera, file, or webcam) that the system records, monitors, and streams from | recording, run, schedule, event, lpr-event, remote-storage | device-management, video-recording, live-streaming, onvif-discovery, snapshot-upload, bif-thumbnails |
| [event](domain/event.md) | Generic typed notification from external systems (motion, sensors, analytics) that drives UI display and trigger automation | device, lpr-event, trigger-config | event-ingestion, triggers |
| [lpr-event](domain/lpr-event.md) | Structured license plate detection record with plate image, pulled from cameras or pushed via webhook | device, event | event-ingestion, triggers |
| [recording](domain/recording.md) | Single MP4 video segment on disk — the fundamental unit of stored footage, queried for playback and synced to remote storage | device, run, schedule | video-recording, playback, remote-storage-sync, bif-thumbnails |
| [remote-storage](domain/remote-storage.md) | Named S3 or HTTP backend configuration that devices reference for uploading snapshots and recordings off-site | device, recording | remote-storage-sync, snapshot-upload |
| [run](domain/run.md) | Uninterrupted recording session grouping contiguous segments into the availability timeline shown in the UI | device, recording | video-recording, playback |
| [schedule](domain/schedule.md) | Weekly time-slot map controlling when a device is allowed to record video or upload snapshots | device | video-recording, device-management, snapshot-upload |
| [trigger-config](domain/trigger-config.md) | Automation rule connecting event sources to target actions — "when X happens on a device, do Y" | device, event | triggers, event-ingestion |
| [user](domain/user.md) | Authenticated person with admin or regular role who accesses ExNVR via web UI or REST API | device | user-auth |

## Features

| Name | Summary | Related concepts | Related features |
|------|---------|-----------------|-----------------|
| [bif-thumbnails](features/bif-thumbnails.md) | Hourly-generated BIF files bundling keyframe thumbnails for video scrubbing previews on the playback timeline | recording, device | video-recording, playback |
| [device-management](features/device-management.md) | Admin feature for creating, configuring, monitoring, and controlling cameras and other video sources | device, schedule | onvif-discovery, video-recording, live-streaming, snapshot-upload |
| [event-ingestion](features/event-ingestion.md) | Webhook and camera-polling paths that bring external signals (motion, LPR, sensors) into the system for display and automation | event, lpr-event, device | triggers |
| [live-streaming](features/live-streaming.md) | Real-time camera video delivery to browsers via HLS and WebRTC, plus on-demand live snapshots | device | video-recording, playback |
| [nerves-firmware](features/nerves-firmware.md) | Embedded Nerves layer that turns a Raspberry Pi into a field-deployable NVR with disk, VPN, UPS, and remote provisioning | device | system-monitoring |
| [onvif-discovery](features/onvif-discovery.md) | Network scanning that finds IP cameras, inspects their config, auto-configures stream profiles, and adds them to ExNVR | device | device-management |
| [playback](features/playback.md) | Timeline-driven viewing of recorded footage via HLS, with snapshot extraction and MP4 clip download | device, recording, run | video-recording, live-streaming, bif-thumbnails |
| [remote-storage-sync](features/remote-storage-sync.md) | Pluggable S3 and HTTP transport layer for uploading snapshots and recordings to external storage backends | remote-storage, recording, device | video-recording, snapshot-upload |
| [snapshot-upload](features/snapshot-upload.md) | Periodic JPEG capture from cameras uploaded to remote storage, plus a Unix socket for local frame consumers | device, remote-storage, schedule | remote-storage-sync, device-management |
| [system-monitoring](features/system-monitoring.md) | CPU, memory, disk, stream stats, and Victron solar/battery metrics exposed via API and Prometheus for dashboards | device | nerves-firmware |
| [triggers](features/triggers.md) | Event-driven automation that evaluates incoming events against source rules and executes target actions like recording control | trigger-config, event, device | event-ingestion, device-management |
| [user-auth](features/user-auth.md) | Authentication (sessions, API tokens, webhooks) and two-role authorization gating all access to the system | user | |
| [video-recording](features/video-recording.md) | Core Membrane pipeline that ingests RTSP/file/webcam streams and writes them as 60-second MP4 segments with disk management | device, recording, run, schedule | live-streaming, playback, remote-storage-sync, bif-thumbnails |
