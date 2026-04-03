---
name: event-ingestion
type: feature
repo: ex_nvr
stack: elixir-phoenix
last_updated_commit: 1868aa39e6b393141b8b57e9a14789d3373f8dd4
paths:
  - ui/lib/ex_nvr/events.ex
  - ui/lib/ex_nvr/events/event.ex
  - ui/lib/ex_nvr/events/lpr.ex
  - ui/lib/ex_nvr_web/controllers/api/event_controller.ex
  - ui/lib/ex_nvr_web/live/generic_events_live.ex
  - ui/lib/ex_nvr_web/live/generic_events/**/*.ex
  - ui/lib/ex_nvr_web/live/lpr_events_list_live.ex
  - ui/lib/ex_nvr/devices/lpr_event_puller.ex
  - ui/lib/ex_nvr_web/lpr/parser.ex
  - ui/lib/ex_nvr_web/lpr/parser/milesight.ex
  - ui/lib/ex_nvr/devices/cameras/http_client/hik.ex
  - ui/lib/ex_nvr/devices/cameras/http_client/milesight.ex
  - ui/lib/ex_nvr_web/user_auth.ex
relates_to:
  concepts: [event, lpr-event, device]
  features: [triggers]
---

## Overview

**Event ingestion** is the feature that brings external signals into ExNVR — motion detected, license plate recognized, door opened, temperature exceeded. These signals arrive as [events](../domain/event.md) (generic) or [LPR events](../domain/lpr-event.md) (license plate recognition), and once inside the system, they can trigger automated actions via the [trigger system](triggers.md).

Events enter ExNVR through three paths:

1. **Generic event webhook** — External systems (cameras, analytics engines, IoT platforms) push events via HTTP POST to `/api/devices/:device_id/events`. Authentication uses a per-user **webhook token** instead of standard session/API auth, making it easy for headless systems to integrate. The entire request body is stored as the event's metadata, so ExNVR doesn't need to know the payload schema in advance.

2. **LPR camera polling** — The `LPREventPuller` GenServer (part of each [device's](../domain/device.md) supervision tree) polls the camera's HTTP API every 10 seconds for new plate detections. This supports Hikvision and Milesight cameras with vendor-specific HTTP clients.

3. **LPR webhook** — External systems can push [LPR events](../domain/lpr-event.md) via `POST /api/devices/:device_id/events/lpr` with webhook token auth. Currently only Milesight camera payloads are parsed; other vendors return a 404.

All three paths feed into the same `ExNVR.Events` context, which stores the event and (for generic events) broadcasts it on PubSub for the trigger system to evaluate.

The ingested events are browsable in the UI through two pages: a generic events table (`/events/generic`) and a dedicated LPR events browser (`/events/lpr`) with plate image thumbnails, snapshot preview, and clip playback.

## How it works

### Generic event ingestion (webhook)

1. External system sends `POST /api/devices/:device_id/events?type=motion_detected&token=<webhook_token>`
2. The `require_webhook_token` plug extracts the token from the `Authorization` header (Bearer) or `token` query param
3. `Accounts.verify_webhook_token/1` checks the token against the database
4. `ExNVRWeb.Plug.Device` loads the device from the route parameter
5. `EventController.create/2` builds the event params:
   - `metadata` ← the entire `conn.body_params` (raw JSON body)
   - `time` ← parsed from `params["time"]` (ISO 8601 with offset → UTC; naive datetime → interpreted in device timezone → UTC; missing → `DateTime.utc_now()`)
   - `type` ← from query params
6. `Events.create_event(device, params)` inserts the row and broadcasts `{:event_created, event}` on the `"events"` PubSub topic
7. The [trigger listener](triggers.md) evaluates the event against configured triggers

### LPR event ingestion (camera polling)

1. When `device.settings.enable_lpr` is `true` and the device has an HTTP URL, the `LPREventPuller` GenServer starts as part of the device supervision tree
2. On init, queries `Events.last_lpr_event_timestamp/1` to find the resume point
3. Every 10 seconds, calls `Devices.fetch_lpr_event/2` which routes to the vendor HTTP client
4. **Hikvision**: `POST /ISAPI/Traffic/channels/1/vehicledetect/plates` with XML `AfterTime` filter → parses XML response via SweetXml → fetches plate images concurrently (max 4) from `/doc/ui/images/plate/{picName}.jpg`
5. **Milesight**: `GET /cgi-bin/operator/operator.cgi?action=get.lpr.lastdata&format=inf` → parses key=value INF format → fetches plate images from `/LPR/{path}` → filters client-side by timestamp
6. Each event + plate image is saved via `Events.create_lpr_event/3` (with `on_conflict: :nothing` for dedup)
7. Plate images are stored as JPEG files under `{storage_address}/ex_nvr/{device_id}/thumbnails/lpr/`

### LPR event ingestion (webhook)

1. `POST /api/devices/:device_id/events/lpr` with webhook token auth
2. `EventController.create_lpr/2` checks `Device.vendor/1` — only `:milesight` is supported
3. `ExNVRWeb.LPR.Parser.Milesight.parse/2` extracts structured fields from JSON: plate number, capture time (naive → device timezone → UTC), direction, list type, bounding box (normalized to [0..1]), confidence, vehicle attributes, and base64-decoded plate image
4. `Events.create_lpr_event/3` stores the event and plate image

## Architecture

### Webhook authentication

Event creation endpoints use a dedicated auth pipeline separate from the standard user authentication:

```
[:api, :require_webhook_token, ExNVRWeb.Plug.Device]
```

The webhook token is a long-lived, manually managed token — one per user, no automatic expiry. Users generate and manage their webhook token through the "Webhook Config" tab on the `/events/generic` page, which shows the full endpoint URL and a cURL example.

### Event browsing UI

**Generic events** (`/events/generic`) — Two tabs:
- **Events tab**: Flop-powered paginated table with filters for device (dropdown), type (text LIKE), and time range. Shows device name, event type, time, and metadata.
- **Webhook Config tab**: Token management (generate/delete), endpoint URL builder with device and type selectors, and a cURL example.

**LPR events** (`/events/lpr`) — Dedicated page with:
- Filterable table (device, capture time range, plate number LIKE)
- Plate image thumbnails in each row (base64 from disk, fallback to default placeholder)
- Capture times displayed in device timezone
- Snapshot preview popup (loads precise snapshot from recording at capture time)
- Clip preview popup (plays 10-second HLS clip: 5s before to 5s after capture time)

**Device events tab** (`/devices/:id/details?tab=events`) — Device-scoped view with automatic `device_id` filter injection via `Flop.nest_filters/2`.

## Integrations

### Camera HTTP clients

| Vendor | LPR endpoint | Format | Direction mapping | Plate image source |
|--------|-------------|--------|-------------------|--------------------|
| Hikvision | `POST /ISAPI/Traffic/channels/1/vehicledetect/plates` | XML | forward→in, reverse→away | `/doc/ui/images/plate/{picName}.jpg` |
| Milesight | `GET /cgi-bin/operator/operator.cgi?action=get.lpr.lastdata&format=inf` | INF (key=value) | 1→in, 2→away | `/LPR/{path}` |

Both clients use `ExNVR.HTTP` for requests with device credentials and fetch plate images concurrently via `Task.async_stream` (max 4 concurrent).

### PubSub → Trigger system

Generic events broadcast `{:event_created, event}` on the `"events"` PubSub topic. The `ExNVR.Triggers.Listener` GenServer subscribes to this topic and evaluates incoming events against configured [trigger rules](triggers.md). LPR events do **not** broadcast on PubSub — they are not trigger sources.

## Data contracts

### Generic event creation

```
POST /api/devices/:device_id/events?type=motion_detected&token=<token>
Content-Type: application/json

{"temperature": 42, "zone": "entrance"}
```

Response: `201` empty body. The entire JSON body becomes the event's `metadata` map.

### LPR event creation (Milesight webhook)

```
POST /api/devices/:device_id/events/lpr?token=<token>
Content-Type: application/json

{
  "plate": "ABC123",
  "time": "2024-04-01 12:00:00",
  "direction": "approach",
  "type": "white",
  "confidence": "95.5",
  "plate_image": "<base64>",
  "resolution_width": "1920",
  "resolution_height": "1080",
  "coordinate_x1": "100",
  "coordinate_y1": "200",
  "coordinate_x2": "300",
  "coordinate_y2": "400",
  "vehicle_color": "white",
  "vehicle_type": "car"
}
```

### Generic event listing

```
GET /api/events?start_date=...&end_date=...&filters[device_id]=...&page=1&page_size=20
```

Response: `{meta: {current_page, page_size, total_count, total_pages}, data: [events]}`

### LPR event listing

```
GET /api/events/lpr?include_plate_image=true&page=1&page_size=20
```

Response: Same structure. When `include_plate_image=true`, each event includes a base64-encoded `plate_image` field (read from disk).

## Configuration

| Config | Location | Default | Notes |
|--------|----------|---------|-------|
| `enable_lpr` | `device.settings` | `false` | Enables the LPR event puller for the device |
| `url` | `device` | — | Camera HTTP URL (required for LPR polling) |
| `timezone` | `device` | `"UTC"` | Used for interpreting naive timestamps in events |
| Polling interval | `LPREventPuller` | 10s | How often to poll the camera for LPR events |
| Webhook token | `users_tokens` table | — | Per-user, no expiry, manually managed |
