---
name: triggers
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/triggers.ex
  - ui/lib/ex_nvr/triggers/**/*.ex
  - ui/lib/ex_nvr_web/live/trigger_config_live.ex
  - ui/lib/ex_nvr_web/live/trigger_config_list_live.ex
  - ui/lib/ex_nvr_web/live/device_tabs/triggers_tab.ex
relates_to:
  concepts: [trigger-config, event, device]
  features: [event-ingestion, device-management, video-recording]
---

## Overview

**Triggers** are ExNVR's event-driven automation system — "when X happens on a camera, do Y." They connect incoming signals (event sources) to automated responses (target actions), enabling workflows like "when a motion event arrives, start recording" or "when any event fires, log a debug message."

The system is built around [trigger configs](../domain/trigger-config.md) — named rules that combine one or more source conditions with one or more target actions, scoped to specific [devices](../domain/device.md). The runtime component is the `ExNVR.Triggers.Listener` GenServer, which subscribes to PubSub topics and evaluates incoming messages against configured triggers in real time.

Triggers are managed through admin-only LiveView pages where admins create trigger rules, configure sources and targets, and then associate triggers with devices via checkboxes on the device details page.

## How it works

### Runtime evaluation flow

1. An [event](../domain/event.md) is created via webhook → `Events.create_event/2` broadcasts `{:event_created, event}` on the `"events"` PubSub topic
2. `ExNVR.Triggers.Listener` (GenServer, subscribed to `"events"` and `"detections"`) receives the message
3. The listener extracts the `device_id` from the message and calls `Triggers.matching_triggers(device_id, message)`
4. `matching_triggers/2` queries all enabled trigger configs associated with that device, deduplicates by ID, and filters to those where at least one source config matches:
   - Resolves the source module via `TriggerSources.module_for(source_type)`
   - Calls `module.matches?(source_config, message)` — e.g., `Sources.Event.matches?/2` checks if the event's `type` equals the configured `event_type`
5. For each matching trigger config, iterates over its enabled `target_configs`
6. Resolves each target module via `TriggerTargets.module_for(target_type)` and calls `module.execute(trigger_message, config, opts)`
7. Errors are caught and logged — a failing target never crashes the listener

### Source types

Currently one registered source:

**Event** (`ExNVR.Triggers.Sources.Event`) — Matches generic webhook events by type. Configuration: `event_type` (string, required). Matches when `{:event_created, %{type: type}}` arrives and `type` equals the configured value.

The `"detections"` PubSub topic is also subscribed to (for future object detection integration), but no source module currently handles detection messages.

### Target types

Two registered targets:

**Log Message** (`ExNVR.Triggers.Targets.LogMessage`) — Logs the trigger message using Elixir's `Logger`. Configurable: `level` (debug/info/warning/error, default: info) and `message_prefix` (default: "Trigger"). Useful for debugging trigger configurations.

**Device Control** (`ExNVR.Triggers.Targets.DeviceControl`) — Controls a device's recording state. Configurable: `action` (start/stop/toggle, default: start).
- `start` → sets device state to `:recording`
- `stop` → sets device state to `:stopped`
- `toggle` → flips based on `Device.recording?/1`

The target operates on the same device that generated the event (using `device_id` from the execution opts). The device loader and state updater functions are injectable via opts for testing.

### Trigger-device association

Triggers are many-to-many with devices via `devices_trigger_configs`. A trigger only fires for events from devices it is associated with. The association is managed per-device in the "Triggers" tab of the device details page, where toggling a checkbox immediately calls `Triggers.set_device_trigger_configs/2`.

The `trigger_config_counts_by_device/0` function provides a count of enabled triggers per device, displayed in the device list UI.

## Architecture

### Listener (`ExNVR.Triggers.Listener`)

A GenServer started in the application supervision tree (not per-device). Subscribes to:
- `"events"` topic — receives `{:event_created, %{device_id: device_id}}`
- `"detections"` topic — receives `{:detections, device_id, dims, detections}`

Error isolation: `catch kind, reason` around each handle_info callback prevents target execution failures from crashing the listener process.

### Pluggable source/target architecture

Both sources and targets follow the same pattern:

1. **Behaviour** — `TriggerSource` / `TriggerTarget` defines `label/0`, `config_fields/0`, `validate_config/1`, and `matches?/2` (sources) or `execute/3` (targets)
2. **Registry** — `TriggerSources` / `TriggerTargets` maintains a list of `{module, key}` tuples and provides `module_for/1` lookup, `type_options/0` for UI dropdowns, and `validate_config/1` for changeset validation
3. **Config validation** — The `TriggerSourceConfig` / `TriggerTargetConfig` changesets delegate to the registry's `validate_config/1`, which resolves the module and calls its `validate_config/1`

Adding a new source or target requires:
1. Implement the behaviour module
2. Add `{Module, :key}` to the registry's `@sources` or `@targets` list

### Pipeline integration

For `recording_mode: :on_event` devices, `Triggers.trigger_recording_configs_for_device/1` returns enabled `TriggerTargetConfig` rows where `target_type == "trigger_recording"`. These are used by the main Membrane pipeline to build one `VideoBufferer` + `Storage` branch per target config, enabling event-triggered recording segments.

## Integrations

### PubSub topics

| Topic | Message | Source |
|-------|---------|--------|
| `"events"` | `{:event_created, %Event{}}` | `ExNVR.Events.create_event/2` |
| `"detections"` | `{:detections, device_id, dims, detections}` | Future detection pipeline |

### Authorization

All trigger CRUD operations require admin authorization via `ExNVR.Authorization.authorize(user, :trigger, action)`. The LiveView pages check authorization on each event handler (create, update, delete, add source/target, toggle device association).

## Data contracts

### Trigger config management (LiveView)

The trigger edit page (`/triggers/:id`) has a two-phase workflow:
1. Create the trigger with a name (and optional enabled toggle)
2. After save, source and target sections appear for adding/removing configs

Source and target forms are rendered dynamically from `config_fields/0` callbacks, supporting `:string`, `:integer`, and `:select` field types with labels, defaults, placeholders, and options.

### Source config example

```json
{
  "source_type": "event",
  "config": {
    "event_type": "motion_detected"
  }
}
```

### Target config example

```json
{
  "target_type": "device_control",
  "config": {
    "action": "start"
  }
}
```

## Configuration

| Config | Location | Notes |
|--------|----------|-------|
| Trigger name | `trigger_configs.name` | Unique, required |
| Trigger enabled | `trigger_configs.enabled` | Default `true`; disabled triggers are never evaluated |
| Target enabled | `trigger_target_configs.enabled` | Individual target enable/disable, independent of parent |
| Device association | `devices_trigger_configs` | Many-to-many; triggers only fire for associated devices |
