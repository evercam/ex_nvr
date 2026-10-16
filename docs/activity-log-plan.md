# Activity & Events — Implementation Plan (v2)

One **Activity** page replaces the Generic Events page. It has two tabs:

- **System:** what ExNVR and the cameras did on their own: power, reboots, disks, camera streams, recording problems, trigger firings, plus the webhook events cameras already send. These are **events**, stored in the existing `events` table.
- **User:** what a person, an API client or the remote server did: logins, config changes, exports, downloads. These are **activity entries**, stored in a new `activity_logs` table.

### What changed since v1

- **System-based activity moves to events.** v1 logged system activity (phase 3) in the activity log. That is now written as events instead, with the same detection logic and noise controls.
- **No occurrence is recorded twice.** An occurrence is either an event or an activity entry, never both. Existing events are kept, under friendlier names.
- **Friendlier event types.** Today's events get readable types (`power.ac_lost` instead of `power` with `state: 0`). Existing rows are migrated, not deleted.
- **Access follows the Generic Events page.** Any logged-in user can see both tabs and the API. v1 was admin-only.
- **Diffs keep only the new state.** Previous values are not stored. Secrets are never shown.
- **One PR per phase, opened one at a time** against `master`.

## 1. Key decisions

| Decision | Choice | Why |
|---|---|---|
| Where system occurrences go | `events` table, with typed names (`stream.offline`, `power.ac_lost`, …) | They are events in today's model. Users can already filter them, read them through `/api/events`, and build triggers on the per-camera ones. |
| Where user actions go | `activity_logs` table | They need an actor (who, from which IP) and a diff, which `events` doesn't model. Inserting into `events` also broadcasts `{:event_created, _}` to the trigger listener, which audit rows must not do. |
| No duplicates | Each occurrence is written once, either as an event or as an activity entry | Phase 3 logged UPS, reboot, power-off and disk occurrences both as an event and as an activity entry. Those now write only the event. |
| What counts as a user action | The actor is a logged-in user (`:user`), an API client (`:api`) or the remote server (`:remote`) | The remote server is an external actor changing the box, like an API user. Changes made by ExNVR itself, such as a trigger stopping a recording or the UPS enabling itself, are not activity entries. |
| When activity is logged | Only when the caller passes an `actor:` | No "system" default actor any more. Boot tasks and pipeline state changes produce no activity entries. |
| Diffs | New values only: `%{"name" => "Front Gate", "credentials.password" => "[REDACTED]"}` | Previous values aren't needed to audit a change and may be sensitive. |
| Access | Same as today's Generic Events page: every logged-in user, both tabs, both APIs | Keeps today's behaviour. Passwords, tokens and keys are always redacted. |
| Old event rows | Renamed in place, on the device (Nerves) at boot | The meaning of the old UPS `state` values depends on the kit's UPS pin defaults, which differ on Giraffe kits and live in the Nerves settings file, not in the database. |
| Retention | Activity kept forever by default, pruning opt-in (`EXNVR_ACTIVITY_RETENTION_DAYS`) | Unchanged. Events retention is unchanged too (none). |

## 2. Page and navigation

- **Route:** `/activity`, with `?tab=system` (default) or `?tab=user`. `/events/generic` redirects to `/activity?tab=system` so bookmarks keep working.
- **Sidebar:** in the **Events** menu, "Generic Events" becomes **Activity**. "Vehicle Plates" stays as its own page.
- **Access:** the same `live_session` as Generic Events today (`:require_authenticated_user`). No admin check.
- **Webhook config:** today it's a third tab. It moves to a **Webhook settings** button in the System tab header that opens it in a modal, because webhook events land in that tab.

### System tab

- **Row:**
  - time;
  - severity badge;
  - friendly label from the type catalog, e.g. "Main power lost", with the type underneath in small text (`power.ac_lost`);
  - device (or "—" for kit-level events);
  - details, the metadata shown in readable form.
- **Webhook events** whose type isn't in the catalog show their type as the label, with severity info, as they do today.
- **Filters:** today's filters (device, type, time range), plus quick filters: All, Power, Cameras (`stream.*`), Recording, Disks, System, Triggers, Webhooks (types outside the catalog).
- **Live updates:** subscribe to the `"events"` topic.

### User tab

- The phase 1 activity list, limited to user categories (`auth`, `user`, `device`, `export`, `config`, `remote`).
- **Columns:** time, severity, category, message + action, actor (email + IP), device, details. In details, changes show as `field → new value`, and redacted fields as "changed".
- **Filters:** category, severity, device, search, time range.
- **Quick filters:** All, Alerts (failed logins, role changes), Logins, Devices, Config changes, Exports.
- **Live updates:** subscribe to the `"activity"` topic.

## 3. User activity (`activity_logs`)

### Data model

The table from v1, with only the user-related categories and actor types:

- `category`: `auth | user | device | export | config | remote`
- `actor_type`: `user | api | remote`
- `actor_id` (string, no FK), `actor_label` (email snapshot), `source_ip`
- `device_id` + `device_name` snapshot, `resource_type` / `resource_id` / `resource_label` snapshot
- `action`, `message`, `severity` (`info | warning | critical`), `metadata` (diff with new values only, reason, params), `time`

Indexes on `time` and on `(category, time)`, `(severity, time)`, `(device_id, time)` and `(actor_id, time)`. No foreign keys, so entries survive deleted devices and users.

### Components (`ui/lib/ex_nvr/activity/`)

| Module | Responsibility |
|---|---|
| `ExNVR.Activity` | `log/1`, `log_sync/1`, `list/2` (Flop, optional `device_id`), `subscribe/0`, `with_actor/2` and `current_actor/0` for actors that cross a GenServer call (Nerves `SystemSettings`). |
| `ExNVR.Activity.Entry` | Schema, Flop config. |
| `ExNVR.Activity.Actor` | `user/2`, `api/2`, `remote/1`, `anonymous/3` (failed logins). |
| `ExNVR.Activity.Diff` | `changes(old, new, opts)` returns the **new** value of each changed field, with nested settings flattened (`stream_config.stream_uri`). Sensitive keys are always `"[REDACTED]"`. |
| `ExNVR.Activity.Writer` | Async batched inserts, flushed on stop. |
| `ExNVR.Activity.Pruner` | Opt-in retention. |
| `ExNVRWeb.ActivityActor` | Builds actors from a conn or a LiveView socket (user, IP captured on mount). |

### Catalog

| Category | Actions |
|---|---|
| `auth` | `auth.login`, `auth.login_failed` (w), `auth.api_login`, `auth.api_login_failed` (w), `auth.logout`, `auth.password_changed`, `auth.password_reset_requested`, `auth.password_reset`, `auth.email_changed`, `auth.webhook_token_created`, `auth.webhook_token_deleted` |
| `user` | `user.created`, `user.updated` (role change = w), `user.deleted` |
| `device` | `device.created`, `device.updated` (+ settings section), `device.deleted`, `device.recording_started`, `device.recording_stopped` (manual only), `device.triggers_changed`, `device.onvif_auto_configured` |
| `export` | `export.started`, `export.completed`, `export.failed` (w), `export.stopped`, `export.disk_mounted`, `export.footage_downloaded`, `export.recording_downloaded` |
| `config` | `config.remote_storage_created` / `_updated` / `_deleted`, `config.trigger_created` / `_updated` / `_deleted`, `config.trigger_source_added` / `_removed`, `config.trigger_target_added` / `_removed`, `config.system_settings_updated` (Nerves; user or remote actor) |
| `remote` | `remote.command_executed` (w), `remote.config_applied`, `remote.provisioned` |

`export.completed` / `export.failed` are finished by the export worker, but they keep the actor who started the export, so they stay in the User tab.

## 4. System events (`events`)

### Type catalog

New module `ExNVR.Events.Types` with one entry per system type: label, severity, group (for the quick filters), and a function that turns the metadata into a readable details line. The UI, the API docs and the webhook guard all read from it.

### Renamed types (PR 3)

| Today | New type(s) | Notes |
|---|---|---|
| `power`, `state: 0/1` | `power.ac_lost` (w) / `power.ac_restored` | Which `state` means lost depends on `ac_pin_default` |
| `low-battery`, `state: 0/1` | `power.low_battery` (c) / `power.battery_ok` | Depends on `battery_pin_default`, which is 1 on Giraffe kits and 0 elsewhere |
| `reboot` | `system.reboot` | Metadata kept (reason, interval, scheduled_at, timezone). `AutoReboot` reads this type. |
| `shutdown` | `power.shutdown`, `reason: "schedule"` | Power schedule |
| `disk`, `connected: 0` | `disk.disconnected` (c) | |

**Migrating existing rows:** a Nerves boot task (`ExNVR.Nerves.EventTypeMigration`) runs once after `SystemSettings` has started.
- It reads the UPS pin defaults from the settings and rewrites the old rows' `type`, deriving the new type from `state`.
- It is idempotent, because it only touches rows with the old types.
- Non-Nerves installs never produced these types, so `ui` needs no migration.
- **Limitation:** if a kit's pin defaults were changed after an event was recorded, that old row could be mapped the wrong way. This is rare, and the plan accepts it.

Trigger sources can't match these events today, because kit-level events have no device and the listener skips them, so no trigger configs need migrating.

### New types (PR 4)

These are the phase 3 detections, written with `Events.create_event` instead of `Activity.log`. Inserts are synchronous, so reboot and power-off events are persisted before the device goes down.

| Group | Types | Source |
|---|---|---|
| Cameras | `stream.offline` (w, after a 30 s grace), `stream.recovered` (+ downtime), `stream.flapping` (w, 5 drops in 10 min) | `StreamMonitor`, from pipeline state telemetry |
| Recording | `recording.paused` / `recording.resumed` (schedule or request), `recording.storage_unwritable` (c), `recording.storage_writable`, `recording.save_failed` (c, max 1 per 10 min), `recording.pipeline_start_failed` (c), `recording.delete_failed` (c, max 1 per hour) | `StorageMonitor`, `Output.Storage`, `Devices`, `DiskMonitor` |
| Disks | `disk.threshold_reached` (w; once per crossing, 5-point margin, max 1 per 6 h), `disk.usage_normal`, `disk.connected` | `DiskMonitor`, `DiskMounter` |
| Power | `power.shutdown`, reason `low_battery` / `ac_failure` (c) | `UPS.power_off`, which records nothing today |
| System | `system.started`, `system.stopping`, `system.unexpected_restart` (c), `system.updated` | `BootRecorder`, `Application.prep_stop/1` |
| Triggers | `trigger.fired` (max 1 per minute per trigger, target and camera; skipped count in `suppressed`) | `Triggers.Listener` |
| Remote | `remote.connected`, `remote.disconnected` (w, max 1 per 10 min) | `RemoteConnection` |

### Rules

- **Trigger loops:** camera-level events (with a `device_id`) now reach the trigger listener. That's a feature: users can trigger on `stream.offline`. The listener ignores `trigger.fired` so a trigger can't fire on its own firing.
- **Webhook guard:** `POST /api/devices/:id/events` rejects types in the system catalog (400), so a webhook can't fake `power.ac_lost` or `system.reboot`.
- **Rate limiting:** the phase 3 ETS rate limiter moves to `ExNVR.RateLimiter`, so both events and activity can use it.
- **Removed:** `StreamMonitor`, `BootRecorder` and `RateLimiter` leave `ExNVR.Activity`. The activity log keeps no system categories.

## 5. API

- `GET /api/events` is unchanged. It now also returns the new types; the OpenAPI spec lists the system types.
- `GET /api/activity` and `GET /api/devices/:device_id/activity` are open to any authenticated user, matching `/api/events`.
- **Old type names:** nothing outside ExNVR filters `/api/events` on `power`, `low-battery`, `reboot`, `shutdown` or `disk`, so PR 3 switches to the new types directly, with no transition period.

## 6. PRs

They are opened **one at a time**, each against `master` after the previous one is merged. Each starts from a fresh branch off the latest `master`, rebuilt from this branch's commits and adjusted to v2. `master` has moved on (`storage.ex`, `devices.ex`, `remote_configurer.ex` and `application.ex` changed), so expect conflicts in PR 2 and PR 4.

| PR | Branch | Contents |
|---|---|---|
| 1. Activity foundation + merged page | `activity/1-foundation` | Migration, `Entry` (user categories), `Activity`, `Writer`, `Actor`, `Diff` (new values only), opt-in `Pruner`. The merged **Activity** page: System tab = today's events list unchanged, User tab = activity list, webhook settings modal, `/events/generic` redirect, sidebar. `/api/activity` + device-scoped, OpenAPI, tests. |
| 2. User actions | `activity/2-user-actions` | `ExNVRWeb.ActivityActor` and the `actor:` option through `Accounts`, `Devices`, `RemoteStorages`, `Triggers`, `Export` and the downloads. Remote server actions (commands, remote config, provisioning). Nerves `SystemSettings` changes via `with_actor`. Nerves test sandbox fix (manual mode). |
| 3. Friendlier events | `activity/3-event-types` | `ExNVR.Events.Types` catalog. Renamed Nerves producers (UPS, power schedule, auto-reboot, disk mounter), with `AutoReboot` reading `system.reboot`. Boot migration of old rows. Friendly System tab (labels, severity, quick filters), webhook guard, OpenAPI types. |
| 4. New system events | `activity/4-system-events` | Phase 3 detections rewritten as events (section 4), `ExNVR.RateLimiter`, trigger loop guard. The phase 3 activity-log versions are removed, so nothing is duplicated. |

Later, not scheduled:
- CSV export;
- health-report alerts as events;
- acknowledging critical events;
- a per-device activity tab.

## 7. Testing

- **PR 1:**
  - `Diff` (new values only, nested, redaction);
  - `Writer`, `Pruner`;
  - LiveView: both tabs, tab switching, filters, live updates, the redirect, and access for a non-admin user;
  - API listing and filters.
- **PR 2:** every hook writes one entry with the right action, actor, IP and resource. No entry without an actor. Secrets are never in metadata.
- **PR 3:**
  - mapping of old rows for both UPS pin defaults (standard and Giraffe);
  - idempotent migration;
  - `AutoReboot` reading `system.reboot`;
  - the webhook guard;
  - System tab labels.
- **PR 4:**
  - `StreamMonitor` grace and flapping;
  - `BootRecorder` (clean stop, crash, version change);
  - `DiskMonitor` margin and restarts;
  - trigger rate limit and loop guard;
  - **one row per occurrence**: UPS, auto-reboot, power schedule and disk tests assert an event and no activity entry.
- **Every PR:** both the `ui` and `nerves_fw` suites pass. The PR description includes a "How to test" section.

## 8. Decisions and open questions

**Decided:**
- System occurrences are events, user actions are activity entries, and nothing is written twice.
- Activity is logged only with an explicit user, API or remote actor.
- The remote server's actions are user activity; its connection drops are system events.
- Both tabs and both APIs are open to every logged-in user, as Generic Events is today.
- Diffs store new values only, and secrets are always redacted.
- Old event rows are renamed by a Nerves boot task.
- One PR per phase, opened one at a time.
- The merged page lives at `/activity`, and `/events/generic` redirects to it.
- Webhook config opens in a modal from the System tab.
- The UPS turning its own monitoring on isn't recorded today, so it stays unrecorded: no event and no activity entry. The phase 3 `with_actor` wrapper around it is dropped.
- No external consumer uses the old event type names, so they're renamed without a transition period.

**Open:** none.
