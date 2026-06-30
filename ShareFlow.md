# surge15 Route Sharing Flow

## Overview

A user can share any saved route with another person by sending them a short code via iMessage. The recipient opens surge15, goes to Settings, taps "Import Route", types in the code, and the route is saved directly into their app. No accounts, no logins, no website, no PIN — just a code that expires after 48 hours.

---

## User Flow

### Sender

1. User opens a route in the app
2. Taps the **Share** button
3. App uploads the route's points (and segments if present) to the surge15 server
4. Server stores the route temporarily and returns a **share code** (e.g. `ABTDFYD3`)
5. App opens iMessage with a pre-composed message:

```
Here's my surge15 track! Open surge15, go to Settings → Import Route, and enter this code:

ABTDFYD3

This code expires in 48 hours.
```

---

### Recipient

1. Opens surge15
2. Goes to **Settings → Import Route**
3. Types in the code (`ABTDFYD3`)
4. Taps **Import**
5. App fetches the route from the server and saves it to SwiftData
6. App navigates to the newly saved route

---

## Server Responsibilities

| Endpoint | Method | Description |
|---|---|---|
| `/share` | POST | Accepts route JSON, stores it, returns `{ code }` |
| `/import` | GET | Accepts `?code=...`, returns full route JSON to the app |

**Storage:** Each shared route entry stores: code, route JSON, created timestamp. Auto-deleted after 48 hours via a TTL or cron job.

---

## How the Two Endpoints Work Together

**1. Sender taps Share → POST `/share`**

The app sends the route data to the server:
```json
{ "name": "My Route", "points": [...], "segments": [...] }
```
The server:
- Generates a random 8-character alphanumeric code (e.g. `ABTDFYD3`)
- Stores `{ code, routeJSON, createdAt }` in the database
- Returns `{ "code": "ABTDFYD3" }` to the app

The app builds the iMessage text and opens the share sheet. Done.

**2. Recipient types code in Settings → GET `/import?code=ABTDFYD3`**

The app calls:
```
GET /import?code=ABTDFYD3
```
The server:
- Looks up the record by code
- Checks the record hasn't expired (48 hours)
- Returns the full route JSON

The app decodes the JSON, creates the `Route` + `RoutePoint` + `RouteSegment` objects, inserts them into SwiftData, and navigates to the new route.

---

## iOS Implementation

### 1. Upload + Share Sheet
- On share tap: POST route data to `/share`, receive `{ code }`
- Build the share message string with the code
- Open with `UIActivityViewController` — user picks iMessage (or any other app)

### 2. Import UI (Settings)
- Settings → "Import Route" row opens a sheet
- Sheet has a `TextField` for the code and an **Import** button
- On import: GET `/import?code=CODE` → decode JSON → create `Route` + `RoutePoint` + `RouteSegment` objects → insert into SwiftData

### 3. Backwards Compatibility
- `segments` in the response is optional — if absent, the app falls back to raw point-based distance calculation (already implemented in `Route.distanceMeters`)
- Any future fields (elevation profiles, etc.) are treated as optional — missing fields are ignored

---

## Data Shape — API Contract

### POST `/share` request body
```json
{
  "name": "My Route",
  "points": [
    { "lat": 40.7851, "lng": -73.9683, "alt": 10.0 },
    { "lat": 40.7854, "lng": -73.9679, "alt": 10.2 }
  ],
  "segments": [
    { "order": 0, "distanceMeters": 500.0, "endLabel": "Turnaround" },
    { "order": 1, "distanceMeters": 500.0, "endLabel": "End" }
  ]
}
```
`segments` and `alt` are optional.

### POST `/share` response
```json
{ "code": "ABTDFYD3" }
```

### GET `/import?code=ABTDFYD3` response
```json
{
  "name": "My Route",
  "points": [
    { "lat": 40.7851, "lng": -73.9683, "alt": 10.0 },
    { "lat": 40.7854, "lng": -73.9679, "alt": 10.2 }
  ],
  "segments": [
    { "order": 0, "distanceMeters": 500.0, "endLabel": "Turnaround" },
    { "order": 1, "distanceMeters": 500.0, "endLabel": "End" }
  ]
}
```
If `segments` was not present in the original POST, omit it from the response entirely.

---

## Security Model

| Threat | Mitigation |
|---|---|
| Someone guessing share codes | 8-char alphanumeric code = 218 trillion combinations — brute force impractical in 48h window |
| Stale data accumulation | All records auto-delete after 48 hours |
| Privacy of location data | Routes are GPS coordinates only — no user identity attached |

---

## Instructions for Server-Side Implementation Agent

This section is a self-contained brief for a Claude agent (or developer) building the backend for the surge15 route sharing feature.

### What You Are Building

A lightweight HTTP API that temporarily stores GPS route data so it can be shared between surge15 app users via a short code. There is no website, no web page to render, no Universal Links. The iOS app talks directly to the API — that's it. There are no user accounts, no authentication, no permanent storage. Data lives for 48 hours and is then deleted.

### Tech Stack

No specific stack is required. Choose whatever you are most comfortable with. Good options:
- **Node.js + Express** with SQLite or PostgreSQL
- **Python + FastAPI** with SQLite or PostgreSQL
- **Go** with SQLite or PostgreSQL

It must be deployable to a server reachable over HTTPS. The base URL will be configured in the iOS app.

---

### Endpoints to Build

#### POST `/share`

Receives a route from the iOS app and stores it temporarily.

**Request body:**
```json
{
  "name": "My Route",
  "points": [
    { "lat": 40.7851, "lng": -73.9683, "alt": 10.0 },
    { "lat": 40.7854, "lng": -73.9679, "alt": 10.2 }
  ],
  "segments": [
    { "order": 0, "distanceMeters": 500.0, "endLabel": "Turnaround" },
    { "order": 1, "distanceMeters": 500.0, "endLabel": "End" }
  ]
}
```

- `segments` is optional — store it if present, omit it if not
- `alt` on each point is optional
- `points` will always be present and will always have at least 2 entries

**What to do:**
1. Generate a random 8-character alphanumeric code (uppercase letters + digits, e.g. `ABTDFYD3`)
2. Store the entire request body as JSON alongside the code and a `created_at` timestamp
3. Return the code

**Response:**
```json
{ "code": "ABTDFYD3" }
```

**Error cases:**
- Return `400` if `points` is missing or has fewer than 2 entries
- Return `400` if `name` is missing or empty

---

#### GET `/import?code=ABTDFYD3`

Called by the iOS app when the recipient types in a code in Settings.

**What to do:**
1. Look up the record by code
2. If not found: return `404`
3. If found but older than 48 hours: return `410 Gone`
4. If valid: return the stored route JSON

**Response:**
```json
{
  "name": "My Route",
  "points": [
    { "lat": 40.7851, "lng": -73.9683, "alt": 10.0 },
    { "lat": 40.7854, "lng": -73.9679, "alt": 10.2 }
  ],
  "segments": [
    { "order": 0, "distanceMeters": 500.0, "endLabel": "Turnaround" },
    { "order": 1, "distanceMeters": 500.0, "endLabel": "End" }
  ]
}
```

If `segments` was not present in the original POST, omit it from the response entirely (do not return an empty array).

---

### Data Storage Schema

```sql
CREATE TABLE shared_routes (
    code        TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    route_json  TEXT NOT NULL,
    created_at  INTEGER NOT NULL  -- Unix timestamp
);
```

`route_json` stores the full original request body as a JSON string.

---

### Expiry / Cleanup

Records older than 48 hours should be deleted. Two approaches:

1. **On read:** When `/import` is called, check `created_at` and return `410` if expired. Run a cleanup job (cron or scheduled task) periodically to delete expired rows.
2. **Database TTL:** If using a database that supports TTL natively (e.g. Redis), set it to 48 hours on insert.

Option 1 with a daily cron job is simplest.

---

### CORS

Both endpoints are called from the iOS app directly (not a browser), so CORS headers are not required.

---

### Summary Checklist

- [ ] `POST /share` — stores route JSON, returns `{ code }`
- [ ] `GET /import?code=...` — returns route JSON or 404/410
- [ ] Expiry: records older than 48 hours return 410 and are periodically cleaned up
- [ ] All responses use `Content-Type: application/json`
- [ ] Server runs over HTTPS
