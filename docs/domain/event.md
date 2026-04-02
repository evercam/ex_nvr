---
name: event
type: concept
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/events/event.ex
  - ui/lib/ex_nvr/events.ex
  - ui/lib/ex_nvr_web/controllers/api/event_controller.ex
  - ui/lib/ex_nvr_web/live/generic_events_live.ex
  - ui/lib/ex_nvr_web/live/generic_events/**/*.ex
  - ui/lib/ex_nvr_web/live/device_tabs/events_list_tab.ex
  - ui/lib/ex_nvr/triggers/sources/event.ex
  - ui/lib/ex_nvr/triggers/listener.ex
  - ui/lib/ex_nvr_web/router.ex
  - ui/lib/ex_nvr_web/user_auth.ex
relates_to:
  concepts: [device, lpr-event, trigger-config]
  features: [event-ingestion, triggers]
---

## Overview

An **Event** is a generic, typed notification associated with a [device](device.md). Events are the primary mechanism for external systems to push information into ExNVR — a camera detects motion, a sensor trips, an analytics engine flags something — and those signals arrive as events via a webhook HTTP endpoint.

Events are intentionally schema-light: they carry a `type` string (e.g. `"motion_detected"`, `"door_open"`), a `time` timestamp, and an arbitrary JSON `metadata` map. This makes them a flexible integration point — any system that can POST JSON can create events, without ExNVR needing to know the event schema in advance.

The event system has two main consumers:

1. **The UI** — Events are browsable in a paginated, filterable table both globally (`/events/generic`) and per-device (device details "Events" tab). Users can filter by device, event type, and time range.

2. **The trigger system** — When an event is created, it is broadcast on the `"events"` PubSub topic. The `ExNVR.Triggers.Listener` GenServer subscribes to this topic and evaluates the event against configured [trigger rules](trigger-config.md). If a trigger's source is configured as an "Event" source with a matching `event_type`, the trigger's target actions fire. This is the primary way events drive automation in ExNVR.

Events are distinct from [LPR events](lpr-event.md), which have their own dedicated schema with structured plate metadata and image storage. Generic events and LPR events share the same context module (`ExNVR.Events`) and controller (`EventController`), but have separate database tables, schemas, and API endpoints.

## Data model

### `ExNVR.Events.Event` (`ui/lib/ex_nvr/events/event.ex`)

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| `id` | integer (auto) | — | Primary key |
| `time` | `:utc_datetime_usec` | `DateTime.utc_now/0` | When the event occurred (auto-generated if not provided) |
| `type` | `:string` | — | Event type identifier (e.g. `"motion_detected"`), required |
| `metadata` | `:map` | `%{}` | Arbitrary JSON payload — stores the full webhook request body |
| `device_id` | `:binary_id` | — | FK to [device](device.md) |
| `inserted_at` | `:utc_datetime_usec` | — | Row creation time (no `updated_at`) |

**Flop integration**: Filterable by `time`, `type`, and `device_id`. Sortable by `time` and `type`. Supports a `device_name` join field for filtering/sorting by the associated device's name. Page-based pagination with a default limit of 20 and max of 50. Default sort is descending by `time`.

**JSON encoding**: The schema derives `Jason.Encoder` excluding `:device` and `:__meta__`, so events can be serialized directly in API responses.

### Filtering

`Event.filter/2` provides query-level filtering by `start_date` and `end_date` string parameters, applying `>=` and `<=` comparisons on the `time` field. This is used in addition to Flop's built-in filtering for the list endpoints.

## API surface

### REST API

Event creation routes are authenticated via **webhook token** (not standard user auth). Query/list routes require standard user authentication.

| Method | Path | Auth | Action |
|--------|------|------|--------|
| `POST` | `/api/devices/:device_id/events` | Webhook token | Create a generic event |
| `POST` | `/api/devices/:device_id/events/lpr` | Webhook token | Create an LPR event (Milesight vendor only) |
| `GET` | `/api/events` | User auth | List/filter generic events (paginated) |
| `GET` | `/api/events/lpr` | User auth | List/filter LPR events (paginated) |

**Event creation** (`EventController.create/2`):
- The entire request body (`conn.body_params`) is stored as the event's `metadata`
- The `time` field is parsed from the request: if an ISO 8601 datetime with offset is provided, it's converted to UTC; if a naive datetime (no offset) is provided, it's interpreted in the device's timezone and then converted to UTC; if missing or unparseable, `DateTime.utc_now()` is used
- Returns `201` with an empty body on success

**Event listing** (`EventController.events/2`):
- Returns `{meta, data}` where `meta` contains `current_page`, `page_size`, `total_count`, `total_pages`
- Supports Flop filter parameters and `start_date`/`end_date` query params

**Webhook token authentication** (`ExNVRWeb.UserAuth.require_webhook_token/2`):
The token can be provided either as a `Bearer` token in the `Authorization` header or as a `token` query parameter. The token is verified against the database via `Accounts.verify_webhook_token/1`. Each user can have at most one webhook token, managed through the UI.

### LiveView pages

| Path | Module | Purpose |
|------|--------|---------|
| `/events/generic` | `GenericEventsLive` | Tabbed view with Events list and Webhook Config tabs |
| `/devices/:id/details?tab=events` | `DeviceTabs.EventsListTab` | Device-scoped events table |

**`GenericEventsLive`** hosts two sub-components:

1. **`EventsList`** — Paginated Flop table showing device name, event type, event time, and metadata. Filterable by device (dropdown), type (text with `LIKE` matching), and time range. Metadata is rendered via a `metadata_display` component.

2. **`WebhookConfig`** — Token management UI where users can generate or delete their webhook token. Displays the full webhook endpoint URL with device and event type parameters, and provides a copyable cURL example. The token can be shown/hidden with a toggle button.

**`DeviceTabs.EventsListTab`** — Embedded in the device details page. Automatically scopes events to the current device using `Flop.nest_filters/2` to inject the `device_id` filter. Supports the same type and time range filters as the global list, but without the device dropdown.

## Business logic

### `ExNVR.Events` context (`ui/lib/ex_nvr/events.ex`)

**Creating events**:

- `create_event/1` — Creates an event without a device association (device_id is nil)
- `create_event/2` — Creates an event associated with a device. After successful insertion, broadcasts `{:event_created, event}` on the `ExNVR.Triggers.events_topic()` (`"events"`) PubSub topic. This broadcast is what triggers the automation system.

**Querying events**:

- `list_events/1` (with `Flop` struct) — Runs a Flop query with device preloading
- `list_events/1` (with params map) — Applies `Event.filter/2` then runs a Flop query with device preloading
- `get_event/1` — Fetches a single event by ID with device preloaded

### PubSub integration with triggers

The event creation flow is the entry point for ExNVR's trigger system:

1. An external system POSTs to `/api/devices/:device_id/events?type=motion_detected&token=...`
2. `EventController.create/2` calls `Events.create_event(device, params)`
3. `do_create_event/2` inserts the row and broadcasts `{:event_created, event}` on `"events"`
4. `ExNVR.Triggers.Listener` (a GenServer subscribed to `"events"`) receives the message
5. The listener calls `Triggers.matching_triggers/2` to find trigger configs whose source matches this event's type
6. `ExNVR.Triggers.Sources.Event.matches?/2` checks if the trigger's configured `event_type` equals the event's `type`
7. For each match, enabled target configs are executed (e.g. HTTP webhook, recording start, etc.)

## Related concepts

- [device](device.md) — Events are associated with a device; the device's timezone is used for parsing naive timestamps
- [lpr-event](lpr-event.md) — A specialized event type with structured plate data, sharing the same context module and controller
- [trigger-config](trigger-config.md) — Trigger rules that can use events as a source, firing target actions when an event of a specific type is created

## Business rules

- **Webhook token is required for event creation** — The `POST /api/devices/:device_id/events` route uses the `:require_webhook_token` pipeline, not standard user authentication. This allows external systems to push events without a full user session.
- **Metadata captures the entire request body** — `conn.body_params` is stored as the event's `metadata` map, preserving whatever JSON the external system sends without schema enforcement.
- **Time parsing respects device timezone** — Naive datetimes (without offset) are interpreted in the device's configured timezone before conversion to UTC. This handles cameras that report local time without UTC offset.
- **Events without a device are possible** — `create_event/1` (single-arity) sets `device_id` to nil, though the REST API always provides a device via the route parameter.
- **Event type is the only required field** — The changeset validates presence of `type` only. `time` auto-generates via `DateTime.utc_now/0` if not provided, `metadata` defaults to `%{}`, and `device_id` is set by the controller.
- **No `updated_at` timestamp** — Events are append-only; the schema uses `timestamps(updated_at: false)`.
- **LPR event creation is vendor-gated** — The `create_lpr` action only supports Milesight cameras. For other vendors, it returns `:not_found`.
