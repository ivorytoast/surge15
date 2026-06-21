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

### Auto-Stop (distance-only, per-lap)

A lap **automatically completes** when `currentLapDistance >= route.distanceMeters`. That's it — no "return within 20 m" check.

The reasoning: the user starts inside the green gate, so the lap's origin is anchored. From there, all that matters is that they cover the loop distance. The user is responsible for actually running the right path (which is what the **segment turnaround alerts** are for, below). The app's job is to count meters and announce events — not to police where they end up.

On auto-stop of the final lap, the UI shows a green check, *"All Laps Complete!"* (or *"Lap Complete!"* for single-lap sessions), final duration and distance, and a Done button.

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

### Iteration 3 — Map-based start gate (✅ shipped)

- `SessionRecordingView` now shows a **MapKit map** in the pre-session ("gate") state.
- The route's defined path is drawn as a **blue polyline**.
- The **20 m start tolerance is rendered as a filled green circle** (`MapCircle`) — the literal "gate" you have to step into.
- The start point is marked with a small **green flag annotation**.
- The user's position uses the standard **`UserAnnotation()`** blue dot.
- The map's rounded border turns **green** when the user is inside the tolerance (visual confirmation that the gate is "open").
- Camera is auto-centered on the start point once on first appearance (~150 m square region), then the user can pan/zoom freely. A `MapUserLocationButton` is available to recenter on themselves.
- Map is **only shown in the gate state** — during the active session it collapses back to the timer/distance view so the user focuses on running, not the screen.

### Iteration 5 — Segments + turnaround alerts (✅ shipped)

The boardwalk problem: an out-and-back loop has no natural visual cue for *"turn around now"*. Without one, the user either runs too far or stops too early and the lap data is junk. Iteration 5 introduces **segments** to solve this.

**New data model**:
- `RouteSegment` (`order`, `distanceMeters`, `endLabel`, `route`). Each route gets at least one segment (`endLabel = "End"`). Marking turnarounds during creation produces interior segments with `endLabel = "Turnaround"`.
- `Route.distanceMeters` now sums segment distances when segments exist (falls back to the raw GPS-trace length for legacy routes saved before iteration 5).
- `Route.segmentEndDistances` — cumulative distances at the end of each segment. The last entry is the lap distance; all prior entries are interior boundaries that should trigger alerts.

**Create flow changes (`CreateRouteView`)**:
- While recording, a prominent orange **"Mark Turnaround"** capsule button appears below the status block.
- Tapping it captures the current cumulative distance as a segment boundary, plays a medium impact haptic, and shows the new segment count + per-segment distance breakdown under the readout (e.g. *"S1: 500 m · S2: 480 m"*).
- The button disables until the user has walked past the 10 m minimum and past the most recent boundary (prevents zero-length segments).
- On save, segments are persisted as `RouteSegment` records. A route with zero turnarounds gets one "End" segment equal to the total distance — semantically the same as iteration 4 routes.

**Session flow changes (`SessionRecordingView`)**:
- **Auto-stop logic dropped the 20 m return check** — see *Auto-Stop (distance-only, per-lap)* above.
- On every GPS update, `checkSegmentBoundaries()` walks the route's interior segment-end distances. The first time `currentLapDistance` crosses one (using a `Set<Int>` of `announcedSegmentsInLap` to avoid duplicate firing), `fireTurnaroundAlert()` runs:
  - **Haptic burst**: one `UINotificationFeedbackGenerator(.warning)` followed by three `UIImpactFeedbackGenerator(.heavy)` impacts spaced 200 ms apart. Loud enough to feel in a pocket.
  - **Full-screen orange overlay** with a giant `arrow.uturn.backward.circle.fill` icon and *"TURN AROUND"* in 56pt heavy rounded text. Fades in over 150 ms, sits for 3 s, fades out over 400 ms.
- At lap completion, `announcedSegmentsInLap` resets so the alerts fire fresh on each new lap.

**Route detail view**:
- A new "Segments" row under the summary shows the count and per-segment distances (e.g. *"2 · 500 m → 500 m"*). A 1-segment route shows *"1 (loop)"*.

**SwiftData migration**: `Route.segments` is an additive relationship (default empty), `RouteSegment` is a new model. Existing routes saved without segments continue to work — `distanceMeters` falls back to the GPS-trace length and `segmentEndDistances` is empty (so no turnaround alerts fire). Lightweight migration handles it.

### Iteration 4 — Multi-lap sessions (✅ shipped)

A single HYROX session is often multiple 1k laps. Before iteration 4, every session was exactly one lap. Now:

**Pre-session**: A lap picker (− / N / +, default **1**, max **20**) appears below the gate status. If the user just wants one lap, they leave it alone and hit Start.

**Active session UI** changes from a single timer to a **multi-stat layout**:
- *"Lap N of M"* header.
- **Current lap time** as the big primary number.
- A row with **distance left in current lap** + **total elapsed** as secondary stats.
- A horizontal strip of **completed lap pills** (L1, L2, …) showing each finished lap's duration in green capsules.

**Lap completion logic** (per lap, same conditions as the original auto-stop):
- When the user has traveled ≥80% of the **route distance for the current lap** AND is back within 20 m of the start, the lap is recorded (timestamp appended to `lapCompletions`).
- If more laps remain, `currentLapStartedAt` and `currentLapStartIndex` reset to "now", and the user keeps running. No screen interruption.
- If it was the final lap, the session auto-stops, saves, and shows *"All Laps Complete!"* (or *"Lap Complete!"* for a 1-lap session).

**Data model additions** (`Session`):
- `targetLaps: Int = 1`
- `lapCompletedAt: [Date] = []` — timestamps marking each lap's completion in order.
- `lapDurations: [TimeInterval]` — computed by walking the `lapCompletedAt` array. Falls back to `[durationSeconds]` for legacy single-lap sessions saved before iteration 4 so analysis continues to work across the migration.

**Route analysis** (`Route`):
- `bestSessionDuration` / `averageSessionDuration` were renamed to **`bestLapDuration` / `averageLapDuration`** — they now flat-map across all sessions' `lapDurations` so multi-lap sessions contribute every lap individually. Comparing a 5-lap session's 3rd lap against a 1-lap session's only lap is apples-to-apples (both are one trip around the loop).
- `RouteDetailView` labels updated to "Best Lap" / "Average Lap".
- Session rows on `RouteDetailView` now show the lap count (e.g. "5 laps") in addition to total time and pace.
- `SessionDetailView` adds a **"Lap Times"** section listing each lap's duration when there's more than one lap.

**SwiftData migration**: `targetLaps` and `lapCompletedAt` are additive properties with default values, so SwiftData's lightweight migration handles existing data without loss.

### Possible next steps

- **Lap-complete haptic + overlay** mirroring the turnaround alert (different color, "LAP DONE" text).
- **Custom segment labels** — let the user name turnarounds during creation (e.g. "Bench", "Tree", "Lifeguard stand").
- **Audible cues** in addition to haptic + visual (system sound or spoken "turn around").
- **Map during the active session** — show user's live trace as they run the loop.
- **Map on `RouteDetailView` and `SessionDetailView`** — visualize the loop and replay sessions.
- **Splits / per-segment pace** during a session (e.g. per-segment time within each lap).
- **Per-session comparison view** ("today vs PB").
- **Background location updates** so the screen can be locked during a run (requires `UIBackgroundModes = location` + `allowsBackgroundLocationUpdates = true` + a `CLBackgroundActivitySession`).

## Project Structure

- `surge15/` — app source (SwiftUI)
- `surge15Tests/` — unit tests (Swift Testing framework)
- `surge15UITests/` — UI tests (XCUIAutomation)
