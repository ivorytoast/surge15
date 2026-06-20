# surge15

A run-tracking iOS app for HYROX-style training without a track.

## North Star Goal

This app fills the gap where you don't have the luxury of a dedicated track or gym — specifically for the **HYROX** competition. You need to create your own "laps" to run 1,000 meters and simulate each HYROX run.

The app must make the following three things **SUPER EASY** and **STRAIGHTFORWARD**. Nothing else matters if these three things are not well done:

1. **Creating your custom "route"** — defining the loop you'll run repeatedly.
2. **Doing an exercise session on that route** — executing one run on a saved route.
3. **Analyzing your past sessions** — seeing how you're improving over time on the same loop.

## Design

The core mental model is **two distinct concepts**, not one:

### Route — the *definition* of where you run

A fixed loop you designed once. A **template**. Created during a one-time setup walk/run, then frozen. Example: *"Backyard 1k loop"*.

- Created **rarely** — once per loop you invent.
- Has a name, a recorded GPS path, and an approximate distance.
- Reused across many sessions.

### Session — *one execution* of a route

A timestamped GPS trace for a single workout, tied back to its parent route.

- Created **frequently** — every time you train.
- Auto-named by timestamp — no naming prompt.
- Stores its own duration, distance, and pace.

### How the three core jobs map to this model

| Job | Flow |
|---|---|
| **1. Create a route** | New Route → walk/run the loop once → name it → save. Setup mode, not training mode. |
| **2. Do a session** | Pick a saved route → walk to the start → big **Start** button → run → **Stop** (or auto-stop). Session auto-saves under that route. |
| **3. Analyze sessions** | Open a route → list of all sessions on it. Personal best, average pace, trend over time. Apples-to-apples because every session shares the same loop. |

### Why this split matters for HYROX

A HYROX athlete reuses the *same* 1k loop dozens of times. The question that actually matters is **"how am I improving on my loop?"** That question only makes sense when sessions are grouped under a route — otherwise you just have a flat pile of unrelated recordings.

## The "Fixed Track" Constraint

The product value comes from the loop being **actually fixed** across sessions — otherwise comparing times is meaningless and the app is just a worse Strava. This drives a few hard rules:

### Gated Start (20 m tolerance)

You **cannot start a session** until your GPS position is within **20 m** of the route's start coordinate.

- 20 m = 2% of a HYROX 1k loop. Loose enough to absorb GPS drift (typically 5–10 m in the open, worse near buildings); tight enough to count as "at the start".
- Before you're in range, the big Start button is **disabled and grey** and displays *"Walk to Start — N m"* updating live.
- Once in range, the button turns **green** and reads "Start". A check + "At Start" label appears above it.
- No "start anyway" escape hatch. This is intentional — see *Design integrity over convenience* below.

### Auto-Stop (loop closure detection)

A session **automatically stops** when both of these are true:

1. You've traveled **≥80%** of the route's defined distance (so the loop is essentially complete).
2. You're back **within the 20 m radius** of the route's start point.

Why this exists: a HYROX-style loop returns to the start. The user is running and not staring at their phone, so the app should detect lap completion and stop itself. The 80% threshold prevents false triggers from circling near the start in the first few steps.

On auto-stop, the UI shows a green check, *"Lap Complete!"*, final duration and distance, and a Done button.

### 10 m Minimum on Create

You cannot save a route that's shorter than **10 m**. The Create flow shows a *"✓ Minimum 10 m"* indicator that goes green when you cross the threshold; tapping Stop below that triggers a *"Route Too Short"* alert.

### Design integrity over convenience

When implementing the gate, the obvious "escape hatch" pattern (a *Start anyway* button that records the session with a warning badge) was **deliberately rejected**. Reasoning:

- If users can start anywhere, sessions on the same route are no longer comparable.
- A warning badge punts the integrity problem onto the user's judgment instead of solving it.
- The whole point of a custom track is that it's fixed. An escape hatch would mean we don't actually believe in the constraint.

If GPS is genuinely broken, the right answer is to move to clearer sky or wait for a better fix — not to compromise the data model.

## Implementation Notes

### Models (`Item.swift`)

- `Route` (name, createdAt, definitionPoints, sessions)
  - `startCoordinate` — first definition point's coordinate.
  - `distanceMeters` — sum of haversine distances between consecutive definition points.
  - `bestSessionDuration`, `averageSessionDuration` — analysis helpers.
  - `Route.totalDistance(coordinates:)` — shared utility, also used by `Session`.
- `RoutePoint` — a sample in a route definition.
- `Session` (startedAt, endedAt, route, points)
  - `durationSeconds`, `distanceMeters`, `paceSecondsPerKilometer`.
- `SessionPoint` — a sample inside a session.
- `CLLocationCoordinate2D.distance(to:)` extension.

`RoutePoint` and `SessionPoint` are intentionally kept as separate models so SwiftData relationships are unambiguous. The duplication is small and worth the clarity.

### Location plumbing (`LocationTracker.swift`)

A single `@Observable` class wrapping `CLLocationManager`:

- `desiredAccuracy = kCLLocationAccuracyBest`
- `activityType = .fitness`
- `distanceFilter = kCLDistanceFilterNone` (streams every update)
- `pausesLocationUpdatesAutomatically = false`

Exposes `recordedLocations: [CLLocation]`, `isRecording`, `authorizationStatus`. Doesn't know anything about Routes or Sessions — views slice its output.

### Views

| View | Purpose |
|---|---|
| `ContentView` | Routes list / home. Empty state + "Create Route" button. |
| `CreateRouteView` | Sheet for one-time route definition. Has the 10 m minimum check. |
| `RouteDetailView` | Summary card (distance, sessions, best/average time) + Start Session row + past sessions list. |
| `SessionRecordingView` | The training screen. Implements the gated start + auto-stop logic. Starts the `LocationTracker` on appear so the gate has data immediately. |
| `SessionDetailView` | Single session breakdown (duration, distance, pace) + raw points. |

### Session recording state

`SessionRecordingView` reuses one `LocationTracker` for both the pre-session gate and the recording itself:

- `tracker.start()` is called on `onAppear` so we get a live position for the gate.
- When the user taps Start, `sessionStartIndex` is set to the current `recordedLocations.count`.
- `sessionLocations` is computed as `recordedLocations.dropFirst(sessionStartIndex)` — everything before the user actually started is discarded at save time.

### iOS configuration

Requires the following Info.plist key on the app target (set via *Target → Info → Custom iOS Target Properties*):

- **`NSLocationWhenInUseUsageDescription`** — *"surge15 needs your location to record your run."* (or similar)

Without this, `requestWhenInUseAuthorization()` is a no-op and the app silently does nothing when the user taps Start.

## Iteration Log

### Iteration 1 — minimal end-to-end recording (✅ shipped)

- Single button to start/stop GPS recording.
- Real-time location capture via `CLLocationManager` delegate.
- Save with a custom name. Listed on the home screen.
- *Limitation:* every recording was a standalone "route" — no Route/Session split, no fixed-track enforcement.

### Iteration 2 — Route/Session split + fixed-track constraints (✅ shipped)

- Separated `Route` (template) and `Session` (execution) models.
- New `RouteDetailView` aggregates per-route stats (best, average, count).
- Auto-named sessions — no naming prompt.
- Gated start with 20 m tolerance.
- Auto-stop at ≥80% loop + within 20 m of start.
- 10 m minimum on route creation.
- "At Start" / "Walk to Start" pre-session UI.

### Possible next steps

- **Mini map** on `RouteDetailView` and `SessionRecordingView` (MapKit polyline of the route + blue dot for current position).
- **Splits / per-segment pace** during a session (e.g. every 100 m of the loop).
- **Per-session comparison view** ("today vs PB").
- **Background location updates** so the screen can be locked during a run (requires `UIBackgroundModes = location` + `allowsBackgroundLocationUpdates = true` + a `CLBackgroundActivitySession`).
- **Haptic feedback** on auto-stop so the user knows the lap closed without looking.

## Project Structure

- `surge15/` — app source (SwiftUI)
- `surge15Tests/` — unit tests (Swift Testing framework)
- `surge15UITests/` — UI tests (XCUIAutomation)
