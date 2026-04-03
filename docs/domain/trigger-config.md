---
name: trigger-config
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/triggers/trigger_config.ex
  - ui/lib/ex_nvr/triggers/trigger_source_config.ex
  - ui/lib/ex_nvr/triggers/trigger_target_config.ex
  - ui/lib/ex_nvr/triggers/device_trigger_config.ex
  - ui/lib/ex_nvr/triggers.ex
  - ui/lib/ex_nvr/triggers/trigger_source.ex
  - ui/lib/ex_nvr/triggers/trigger_sources.ex
  - ui/lib/ex_nvr/triggers/trigger_target.ex
  - ui/lib/ex_nvr/triggers/trigger_targets.ex
  - ui/lib/ex_nvr/triggers/sources/event.ex
  - ui/lib/ex_nvr/triggers/targets/log_message.ex
  - ui/lib/ex_nvr/triggers/targets/device_control.ex
  - ui/lib/ex_nvr/triggers/listener.ex
  - ui/lib/ex_nvr_web/live/trigger_config_live.ex
  - ui/lib/ex_nvr_web/live/trigger_config_list_live.ex
  - ui/lib/ex_nvr_web/live/device_tabs/triggers_tab.ex
relates_to:
  concepts: [device, event]
  features: [triggers, event-ingestion]
---

## Overview

A **Trigger Config** is a named automation rule that connects event sources to target actions. It is the configuration layer of ExNVR's event-driven automation system — "when X happens, do Y." For example: "when a `motion_detected` event arrives on a camera, start recording on that camera" or "when any event arrives, log a message."

The trigger system is designed as a pluggable source-to-target pipeline with three separate entities:

1. **TriggerConfig** — The top-level rule with a name and enabled/disabled flag
2. **TriggerSourceConfig** — One or more source conditions attached to a trigger (what events to match)
3. **TriggerTargetConfig** — One or more target actions attached to a trigger (what to do when matched)

Triggers are associated with [devices](device.md) through a many-to-many join table (`devices_trigger_configs`). A trigger only fires for events coming from a device it is associated with. This association is managed per-device via the "Triggers" tab on the device details page, where admins toggle which triggers apply to each device.

The runtime execution flow is handled by `ExNVR.Triggers.Listener`, a GenServer that subscribes to the `"events"` and `"detections"` PubSub topics. When a message arrives, the listener finds all enabled trigger configs for the originating device, checks if any source config matches the message, and executes all enabled target configs on matching triggers.

The source/target system is designed with behaviours (`TriggerSource` and `TriggerTarget`) and registries (`TriggerSources` and `TriggerTargets`), making it straightforward to add new source and target types by implementing the behaviour and registering the module.

## Data model

### `ExNVR.Triggers.TriggerConfig` (`ui/lib/ex_nvr/triggers/trigger_config.ex`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | integer (auto) | — | Primary key |
| `name` | `:string` | — | Unique name, required |
| `enabled` | `:boolean` | `true` | Whether this trigger is active |
| `inserted_at` | `:utc_datetime_usec` | — | Row creation time |
| `updated_at` | `:utc_datetime_usec` | — | Row update time |

**Associations:**
- `has_many :source_configs` → `TriggerSourceConfig`
- `has_many :target_configs` → `TriggerTargetConfig`
- `many_to_many :devices` → `Device` via `DeviceTriggerConfig` (with `on_replace: :delete`)

### `ExNVR.Triggers.TriggerSourceConfig` (`ui/lib/ex_nvr/triggers/trigger_source_config.ex`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | integer (auto) | — | Primary key |
| `source_type` | `:string` | — | Key identifying the source module (e.g. `"event"`), required |
| `config` | `:map` | `%{}` | Source-specific configuration (e.g. `%{"event_type" => "motion_detected"}`) |
| `trigger_config_id` | integer | — | FK to TriggerConfig, required |

The changeset delegates validation to `TriggerSources.validate_config/1`, which resolves the `source_type` to its module and calls `validate_config/1` on it, replacing the `:config` field with the validated result.

### `ExNVR.Triggers.TriggerTargetConfig` (`ui/lib/ex_nvr/triggers/trigger_target_config.ex`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | integer (auto) | — | Primary key |
| `target_type` | `:string` | — | Key identifying the target module (e.g. `"log_message"`), required |
| `config` | `:map` | `%{}` | Target-specific configuration (e.g. `%{"level" => "info"}`) |
| `enabled` | `:boolean` | `true` | Individual target enable/disable |
| `trigger_config_id` | integer | — | FK to TriggerConfig, required |

### `ExNVR.Triggers.DeviceTriggerConfig` (`ui/lib/ex_nvr/triggers/device_trigger_config.ex`)

Join table with a composite primary key of `(device_id, trigger_config_id)`. No additional fields.

## Business logic

### `ExNVR.Triggers` context (`ui/lib/ex_nvr/triggers.ex`)

**TriggerConfig CRUD:**
- `create_trigger_config/1` — Creates a new trigger config
- `update_trigger_config/2` — Updates name and/or enabled flag
- `delete_trigger_config/1` — Deletes the trigger config (cascades to source/target configs via DB)
- `get_trigger_config!/1` — Fetches with preloaded `source_configs`, `target_configs`, and `devices`
- `list_trigger_configs/0` — All configs ordered by `inserted_at`, fully preloaded

**Source/Target Config CRUD:**
- `create_source_config/1`, `delete_source_config/1` — Add/remove source conditions
- `create_target_config/1`, `delete_target_config/1` — Add/remove target actions

**Device association:**
- `set_device_trigger_configs/2` — Replaces all trigger associations for a device: deletes existing `DeviceTriggerConfig` rows and inserts new ones for the given trigger config IDs
- `trigger_config_counts_by_device/0` — Returns `%{device_id => count}` of enabled triggers per device (used by the device list UI to show trigger counts)
- `trigger_configs_for_device/1` — Returns enabled triggers for a device (with sources and targets preloaded)
- `all_trigger_configs_for_device/1` — Returns all triggers for a device (enabled and disabled)
- `trigger_recording_configs_for_device/1` — Returns enabled `TriggerTargetConfig` rows where `target_type == "trigger_recording"` for a device (used by the Membrane pipeline to build on-event recording branches)

**Matching:**
- `matching_triggers/2` — The core runtime function. Given a `device_id` and a PubSub message, finds all enabled trigger configs for that device, deduplicates by ID, and filters to those where at least one source config matches the message via `module.matches?(config, message)`.

### Source behaviour and implementations

The `TriggerSource` behaviour (`ui/lib/ex_nvr/triggers/trigger_source.ex`) defines:
- `label/0` — Human-readable name for the UI
- `config_fields/0` — List of field descriptors for dynamic form rendering
- `validate_config/1` — Validates and normalizes the config map
- `matches?/2` — Tests whether a PubSub message matches this source's criteria

**Registry** (`TriggerSources`): Currently one registered source:
- `{Sources.Event, :event}` — Matches [generic events](event.md) by `event_type`

The `Sources.Event` implementation matches `{:event_created, %{type: type}}` messages where the event's `type` equals the configured `event_type` string.

### Target behaviour and implementations

The `TriggerTarget` behaviour (`ui/lib/ex_nvr/triggers/trigger_target.ex`) defines:
- `label/0` — Human-readable name
- `config_fields/0` — Field descriptors for forms
- `validate_config/1` — Validates and normalizes config
- `execute/3` — Performs the action. Receives the raw trigger message, the validated config map, and opts including `target_config_id` and `device_id`.

**Registry** (`TriggerTargets`): Two registered targets:

1. **`Targets.LogMessage` (`:log_message`)** — Logs the trigger message at a configurable level (`debug`/`info`/`warning`/`error`) with a configurable message prefix. Useful for debugging.

2. **`Targets.DeviceControl` (`:device_control`)** — Controls a device's recording state. Supports three actions:
   - `"start"` — Sets device state to `:recording`
   - `"stop"` — Sets device state to `:stopped`
   - `"toggle"` — Flips between `:recording` and `:stopped` based on current state
   
   The device and state updater functions are injectable via opts (for testing). The target operates on the same device that generated the event (using `device_id` from opts).

### Runtime listener (`ExNVR.Triggers.Listener`)

A GenServer started in the application supervision tree. On init, subscribes to:
- `"events"` topic — receives `{:event_created, %{device_id: device_id}}` messages
- `"detections"` topic — receives `{:detections, device_id, dims, detections}` messages

For each message, calls `matching_triggers/2` to find trigger configs that match, then iterates over each matching config's enabled `target_configs`, resolving the target module via `TriggerTargets.module_for/1` and calling `execute/3`. Errors are caught and logged without crashing the listener.

## API surface

### LiveView pages

| Path | Module | Access | Purpose |
|------|--------|--------|---------|
| `/triggers` | `TriggerConfigListLive` | Admin | Table listing all triggers with name, enabled status, source/target/device counts |
| `/triggers/new` | `TriggerConfigLive` | Admin | Create trigger form (name + enabled) |
| `/triggers/:id` | `TriggerConfigLive` | Admin | Edit trigger: update name/enabled, add/remove sources and targets |
| `/devices/:id/details?tab=triggers` | `DeviceTabs.TriggersTab` | Admin | Toggle trigger associations for a device via checkboxes |

**`TriggerConfigLive`** — The create/edit page has a two-phase UX:
1. First, the trigger must be saved with a name (and optional enabled toggle)
2. After creation, the page shows "Event Sources" and "Targets" sections where sources and targets can be added/removed individually

Source and target config forms are rendered dynamically from the `config_fields/0` callbacks of each registered module, supporting `:string`, `:integer`, and `:select` field types.

**`DeviceTabs.TriggersTab`** — Shows all trigger configs as a checklist. Toggling a checkbox immediately calls `Triggers.set_device_trigger_configs/2` to update the device's associations. Shows a "Saved" confirmation message after each toggle.

All trigger management actions (create, update, delete, add source/target) are gated by `ExNVR.Authorization.authorize(user, :trigger, action)`.

## Storage

### Database

Four SQLite tables:

| Table | Purpose |
|-------|---------|
| `trigger_configs` | Top-level trigger rules (name, enabled) |
| `trigger_source_configs` | Source conditions with type and JSON config |
| `trigger_target_configs` | Target actions with type, JSON config, and enabled flag |
| `devices_trigger_configs` | Many-to-many join between devices and trigger configs |

## Related concepts

- [device](device.md) — Triggers are associated with devices; events from associated devices are evaluated against trigger sources
- [event](event.md) — The primary trigger source; generic events broadcast on PubSub are matched by the Event source

## Business rules

- **Name is unique** — Enforced by a unique constraint on `trigger_configs.name`.
- **Disabled triggers are never evaluated** — `matching_triggers/2` and `trigger_configs_for_device/1` both filter by `tc.enabled == true`. Disabled triggers are visible in the UI but inert.
- **Individual target enable/disable** — Each `TriggerTargetConfig` has its own `enabled` flag, independent of the parent trigger's enabled state. The listener only executes targets where `target.enabled == true`.
- **Source validation is module-driven** — The `TriggerSourceConfig` changeset delegates to `TriggerSources.validate_config/1`, which resolves the source module and calls its `validate_config/1`. Unknown source types produce a changeset error.
- **Target validation is module-driven** — Same pattern as sources, via `TriggerTargets.validate_config/1`.
- **Device association is replace-all** — `set_device_trigger_configs/2` deletes all existing associations for the device and inserts the new set. This means toggling one trigger off and on is a full replace, not a diff.
- **Authorization on `:trigger` resource** — All trigger operations (create, update, delete) require admin authorization via `authorize(user, :trigger, action)`. The TriggersTab checks `:trigger, :update` for toggling device associations.
- **Listener error isolation** — The listener catches exceptions from target execution (`catch kind, reason`) and logs them, preventing a buggy target from crashing the listener and affecting other triggers.
