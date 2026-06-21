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

### Iteration 9 — TabView + tie-safe badges + name truncation (✅ shipped)

Three changes that move the app from a flat single-screen toolbar to a proper iOS layout, plus two small data-correctness fixes.

#### TabView shell with center CTA

`ContentView` is now a thin `TabView` shell with three tab items:
| Tag | Content | Tab item |
|---|---|---|
| 0 | `RoutesHomeView` (was the bulk of old ContentView, minus calendar) | "Routes" · `figure.run` |
| 1 | Action-only (`Color.clear`) | "Create" · `plus.circle.fill` — sits visually in the center |
| 2 | `SessionsHomeView` (NavigationStack + `CalendarHomeView`) | "Sessions" · `calendar` |

The middle tab doesn't navigate. Selecting it triggers `showingCreateRoute = true` (presenting `CreateRouteView`) and then immediately reverts `selectedTab` to `lastValidTab`. Net effect: the "+" feels like a proper CTA button that drops the user into route creation regardless of which tab they were on.

The Create Route sheet is hoisted up to `ContentView` so it works from any tab. The empty-state CTA inside `RoutesHomeView` uses the same binding (`@Binding var showingCreateRoute: Bool`), so there's only one sheet trigger source of truth.

#### Side effects of the tab restructure

- `HomeViewMode` dropped `.calendar` (now its own tab). The Routes tab's leading toolbar button reverted to a simple single-button toggle between map and list (no Menu picker needed for two options).
- The Routes tab's primary-action "+" toolbar item was **removed** — the create CTA lives in the tab bar now.
- `SessionsHomeView` is a thin wrapper around `CalendarHomeView` providing its own NavigationStack and the `navigationDestination(for: SurgeSession.self)` registration. Each tab owns its navigation independently.

#### Tie-safe badge colors

The previous gradient used `rank / (total - 1)`, so three routes tied at "1 session" each rendered as green / amber / red — wrong. Fixed with a per-render `badgeColors()` pass:

```swift
for each route in display order:
    if value == previousValue: use previousColor
    else:                       use gradientColor(rank: i, total: n)
```

Implemented via `sortValue(for: route)` (`Double` — meters for distance sorts, session count for frequency). The pass also handles the unavailable case (no `userCoordinate`, no `startCoordinate`) by emitting `systemGray3` and resetting the tie tracker so the next non-unavailable run starts a fresh color thread.

Examples after the fix:
- 3 routes all used 1× → **all green**.
- Sessions counts `[5, 5, 2, 1, 1]` → green, green, amber-ish, red-ish, red-ish.
- Distances `[10 m, 20 m, 30 m]` → unchanged from before (green / amber / red), since none tie.

#### Route name truncation in compact rows

Long names like *"Hamill Park east lap with the loop around the playground"* were blowing out row layouts. A small file-private helper `truncatedRouteName(_:limit:)` clamps the displayed name to **16 characters**, appending `…`. Applied to:
- `RoutesHomeView.routeRow` (list view)
- `ClusterSheet` rows

Detail views (`RouteDetailView` title, `EditRouteView`, `RoutePeekSheet`, `SessionRecordingView`) keep the full name — truncation is row-only.

### Iteration 8 — Surge Sessions + calendar (✅ shipped)

Adds a day-level workout container above the route execution. **HYROX involves 8 functional exercises** (rowing, lunges, etc.) and a typical training day combines multiple efforts on multiple routes — a single `Session` per route isn't enough granularity to roll a day up coherently.

#### Mental model

```
SurgeSession (a day's workout — Jun 20)
├── Session  (3-lap run on Backyard 1k @ 7:15 am)
├── Session  (1-lap run on Boardwalk @ 7:32 am)
└── Session  (future: rowing, lunges, etc.)
```

`Session` keeps its existing meaning (one execution of one `Route`). `SurgeSession` is the new day container — designed to also hold non-run exercises in future iterations.

#### Naming

The user's term *"surge session"* is the day container. The pre-existing `Session` (route execution) was **deliberately not renamed** because future non-run exercises will share that `Session` type (or sit alongside it).

#### Data model (`Item.swift`)

- `SurgeSession` (`name`, `date`, `createdAt`, `sessions: [Session]`).
  - `date` is **anchored to `startOfDay`** so "today" comparisons can use `Calendar.isDate(_:inSameDayAs:)`.
  - `name` is auto-generated at creation via `SurgeSession.autoName(for:)` — picks a time-of-day prefix (*"Morning"*, *"Midday"*, *"Afternoon"*, *"Evening"*, *"Night"*, *"Late Night"*) and appends the formatted month/day. Editable later.
  - Aggregates: `sortedSessions`, `totalDurationSeconds`, `totalDistanceMeters`.
- `Session.surgeSession: SurgeSession?` — new optional reverse relationship. Enforced non-nil at creation time in `SessionRecordingView.saveSession()` (the picker guarantees a `SurgeSession` is selected before recording begins).
- **No backward-compat migration**: per user direction, this iteration assumes the data store can be wiped. Existing pre-iteration-8 builds will need to delete + reinstall the app rather than have the new schema accommodate orphan sessions.

#### Required attachment flow

Tapping **Start Session** on `RouteDetailView` no longer pushes `SessionRecordingView` directly. Instead it presents `SurgeSessionPickerSheet`:

- Top row: **+ New Surge Session** (creates a `SurgeSession` with `autoName(for: now)` and `date: startOfDay(now)`, inserts it, and immediately selects it).
- Below: a list of all **today's** surge sessions (filtered via `Calendar.isDate(_:inSameDayAs:)` against `Date()`).
- An empty-day shows guidance text pointing to the **+ New** button.

After selection, the sheet sets `pendingSurge` and dismisses. The view's `onDismiss:` handler then sets `recordingSurge`, triggering `.navigationDestination(item:)` to push `SessionRecordingView(route:, surgeSession:)` with both anchors. This avoids the SwiftUI sheet+navigation race the rest of the app deals with the same way.

`SessionRecordingView.saveSession()` now sets both sides of the relationship (`session.surgeSession = surgeSession` + appending to `surgeSession.sessions`).

#### Calendar mode

A third home view mode joins map and list. The toolbar's leading button is now a `Menu` (was a single toggle) with a `Picker` over `HomeViewMode.allCases` so all three options are visible.

`CalendarHomeView`:
- A graphical `DatePicker(displayedComponents: .date)` at the top — fully scrollable month view.
- Below it, a `List` section showing `SurgeSession`s whose `date` matches the picker's selection (via `Calendar.isDate(_:inSameDayAs:)`), or *"No surge sessions on this day."* when empty.
- Each row shows the surge session's name, started time, session count, and total active time.
- Tapping a row pushes `SurgeSessionDetailView` via `navigationDestination(for: SurgeSession.self)` registered on the home `NavigationStack`.

#### SurgeSessionDetailView

- "Surge Session" section: editable name `TextField` (auto-saves via `@Bindable`), read-only date, started time, session count, total active time, total distance.
- "Sessions" section: each `Session` shown with its route name, start time, duration, and lap count. Tapping pushes the existing `SessionDetailView`.
- Swipe-to-delete removes individual sessions from the surge session (cascades naturally — they're deleted from the route side too via the same relationship).
- "Delete Surge Session" row at the bottom (red, with confirmation) — deletes only the surge session record. The underlying `Session`s remain attached to their routes because the relationship uses `.nullify` (not `.cascade`) — surge sessions are a metadata grouping, not the owner of the work.

### Iteration 7 — Pin clustering + sortable list (✅ shipped)

Two distinct improvements layered onto the iteration-6 home screen.

#### Pin clustering on the map

Routes whose start points fall within **100 m of each other** collapse into a single **cluster pin** that displays the count. Tapping a cluster opens a sheet that lists the routes; tapping one of them drops into the existing `RoutePeekSheet` for that route.

- New types in `ContentView.swift`:
  - `RouteCluster { routes: [Route], coordinate: CLLocationCoordinate2D }` — a stable group, with a deterministic `id` built from sorted persistent IDs of its members so SwiftUI's `ForEach` doesn't tear down annotations across redraws.
  - `RouteClusterSelection` — a small `Identifiable` wrapper so the cluster sheet can be driven by `.sheet(item:)`.
- `clusterRoutes(_:withinMeters:)` is a top-level function performing **single-link connected-components** clustering via BFS: A is grouped with B if they're within the threshold, and transitively with C if B and C are within the threshold (even if A and C aren't). O(n²) — fine for the small route counts we expect.
- A cluster's pin coordinate is the **centroid** of its member start points so the pin doesn't visually favor one route.
- Visual:
  - Single-route cluster → existing `startPin` (white circle, green flag).
  - Multi-route cluster → larger green-circle-on-white badge with the count in heavy rounded text.
- Tap dispatch (`tapped(_:)`):
  - Singleton → `peekRoute = route` (existing peek sheet).
  - Multi → `clusterPeek = RouteClusterSelection(routes:)`, opens the new `ClusterSheet`.
- `ClusterSheet` is a list with `route.name`, distance, and session count per row. Selecting a row sets `pendingPeek = route`, dismisses the sheet, and `handleClusterDismiss()` then promotes it to `peekRoute` — same deferred-dismiss pattern used elsewhere to avoid sheet+navigation race conditions.

#### Sort badge per row (rank-colored)

Each row in the list view now has a **leading 64×48 rounded badge** that displays the sort value for that row, colored on a green→amber→red gradient by its rank in the sorted list.

- Value shown:
  - **Distance From You** → distance to start, formatted (`"10 m"`, `"1.2 km"`).
  - **Most Frequently Used** → session count with `x` suffix (`"3x"`).
  - **Lap Distance** → loop length, formatted (`"50 m"`, `"1 km"`).
- Color is a **3-stop linear interpolation** between three RGB stops at `t=0`, `t=0.5`, `t=1` where `t = rank / (total - 1)`:
  - Green `(0.20, 0.70, 0.30)` at the top of the sort.
  - Amber `(0.95, 0.70, 0.10)` at the midpoint — covers "yellow/orange" without locking into a single hue.
  - Red `(0.85, 0.20, 0.20)` at the bottom.
- **Single-row list** is fully green (no gradient to compute).
- **Unavailable badges** (e.g. "Distance From You" sorted but no user location, or no `startCoordinate`) render as **system grey** with `"—"` so the row is still informative.
- Fixed-width badge so the digits line vertically down the list; `minimumScaleFactor(0.7)` to gracefully shrink long values like `"1.2 km"`.
- The previous redundant inline "X away" label was removed from row metadata — the badge supersedes it.

#### Sortable list view

The list mode now shows a prominent sort pill above the list — *"Sorted by: <current sort>"* with a chevron. Tapping it opens a `Menu` `Picker` of three options:

| Sort | Behavior |
|---|---|
| **Distance From You** | Ascending by haversine distance from `userCoordinate` to each route's `startCoordinate`. Routes without a start coordinate sort to the bottom (distance `.infinity`). If location is unavailable, falls back to the default query order and an orange warning triangle appears next to the pill. |
| **Most Frequently Used** | Descending by `route.sessions.count`. Ties broken by `createdAt` descending. |
| **Lap Distance** | Ascending by `route.distanceMeters` (shortest first). |

- `sort: RouteSort` is local view `@State` (not persisted across launches — change preference here if you want it sticky).
- When sorted by **Distance From You**, each row gains a third inline label like *"123 m away"* so the sort criterion is reinforced in the data, not just the header.
- `onDelete` was updated to map the displayed `IndexSet` (against `sortedRoutes`) back to the model objects before calling `modelContext.delete(_:)` — otherwise swipe-to-delete would target wrong items when sorted.

### Iteration 6 — Map-based home screen (✅ shipped)

The home screen is now a map of your training area instead of a list. Your routes appear as start-gate pins, and tapping one offers a quick *Use / Edit* choice.

**New views**:
- `RoutePeekSheet` — compact bottom sheet (`.presentationDetents([.height(240)])`) shown when the user taps a pin. Title is the route name, subtitle is *"Loop distance · N sessions · M segments"*. Two large capsule buttons: **Use Route** (green, play icon) and **Edit Route** (grey, pencil icon).
- `EditRouteView` — scoped to **rename + delete**. Anything heavier (re-recording the path, editing segments) is deliberately out of scope. The form shows read-only stats (distance, segments, sessions, created date) so the user has context while deciding to delete.

**`ContentView` rewrite**:
- Two modes: `.map` (default) and `.list`. A toolbar button in the leading position toggles between them (`map.fill` / `list.bullet` icon).
- **Map mode**:
  - `Map(position: $cameraPosition)` with `.mapStyle(.standard(elevation: .flat))`.
  - One `Annotation` per route at its `startCoordinate`, rendered as a green-flag-in-white-circle pin (same visual language as the in-session start gate).
  - The pin is wrapped in a `Button` so taps reliably set `peekRoute`.
  - `UserAnnotation()` for the blue dot.
  - `MapUserLocationButton` + `MapCompass` in `.mapControls`.
- **List mode**: the previous list UI, intact.
- **Empty state** (`routes.isEmpty`): `ContentUnavailableView` with a **"Create Route"** prominent bordered button — no toggle is shown because mode is irrelevant.

**Initial camera positioning**:
- On appear, `tracker.requestSingleLocation()` is called — a lightweight one-shot fix (via `CLLocationManager.requestLocation()`) rather than continuous streaming, since the home screen doesn't need a live feed.
- When the location arrives, `centerOnUserIfNeeded()` sets `cameraPosition = .region(...)` centered on the user with a **3 km** square extent (`latitudinalMeters: 3000, longitudinalMeters: 3000`). The `didCenterOnUser` flag prevents repeated recentering if the user pans the map.
- Before the location resolves, the camera shows a wide fallback region (continental US-ish) so the map isn't blank.

**Location denied / unavailable**:
- A semi-transparent **black overlay** covers the map with `location.slash.fill` icon, *"Location Unavailable"* title, an explanation, and a white **"Switch to List View"** capsule button.
- The overlay is also tappable (its `Rectangle` content shape catches taps anywhere) — tapping switches to list mode. This matches the user's spec: *"It greys out the screen and allows the user to press the map to see the list view (or recommends user to switch to the list view)."*

**Sheet → navigation pattern**:
- Directly pushing a NavigationStack destination from inside a sheet's button handler is unreliable in SwiftUI. The peek sheet uses a deferred pattern: it sets `pendingOpen` or `pendingEdit`, then dismisses itself. The sheet's `onDismiss:` closure (`handlePeekDismiss()`) then either `path.append(route)` (for Use) or sets `editingRoute = route` (for Edit). This avoids the sheet+navigation race.

**`LocationTracker` addition**:
- `requestSingleLocation()` — handles the not-determined case by storing a `pendingSingleLocation` flag, then issuing the request from `locationManagerDidChangeAuthorization(_:)` once auth resolves. Already-authorized callers fire `manager.requestLocation()` immediately.

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

- **Non-run exercises inside a Surge Session** — HYROX has 8 functional exercises (rowing, lunges, sled push/pull, burpees, etc.). Probably a new `Exercise` protocol or a separate `ExerciseRecord` model holding type + duration + reps, attached to a `SurgeSession` the same way `Session` is.
- **Default surge session for today** — auto-select the most recent surge session for today if one exists, instead of showing the picker. Reduces a tap when doing back-to-back runs.
- **Calendar day badges** — visual dots/colors on days that have surge sessions so the user can scan a month at a glance. The graphical `DatePicker` doesn't support this natively; would need a custom calendar grid.
- **Persist sort preference** across launches (currently `RouteSort` is view-local `@State`).
- **Zoom-aware clustering threshold** — currently a flat 100 m real-world distance regardless of zoom level. At very tight zooms, pins that are 80 m apart could fairly be shown separately.
- **"Fit all routes" button** that adjusts the camera to a region encompassing every route.
- **Sort list by best lap time** for analysis-first use of the list view.
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
