# surge15

A run-tracking iOS app for HYROX-style training without a track.

## North Star Goal

This app fills the gap where you don't have the luxury of a dedicated track or gym — specifically for the **HYROX** competition. You need to create your own "laps" to run 1,000 meters and simulate each HYROX run.

The app must make the following three things **SUPER EASY** and **STRAIGHTFORWARD**. Nothing else matters if these three things are not well done:

1. **Creating your custom "route"** — defining the loop you'll run repeatedly.
2. **Doing an exercise session on that route** — executing one run on a saved route.
3. **Analyzing your past sessions** — seeing how you're improving over time on the same loop.

## Two Core Actions

The app does two things. Everything else exists to support them.

### 1. Run a Route

Go outside. Run your loop. See how fast you did it.

```
⚡ Surge tab
  → "Run a Route"
  → Routes tab — tap a route pin or list row
  → Peek sheet — tap Go
  → Walk to start line (GPS gates the start)
  → Countdown → Running → Auto-lap → Done
  → Back to workout timeline
```

**What makes this work:**
- A saved Route (your personal GPS loop)
- GPS fix within 20 m of the start line before you can begin
- Auto-lap triggers the moment you hit the loop distance — no manual tap
- Turn alerts fire at each segment boundary so you know when to change direction

### 2. Execute a Plan

Follow a structured workout. Run, exercise, run, exercise, repeat.

```
⚡ Surge tab
  → "Execute a Plan"
  → Plans tab — tap a plan
  → Pick a route → tap Start
  → Workout timeline opens
  → Work through each exercise in order
  → Each item: Start → Countdown → Do the work → Done → next item
  → Workout Complete
```

**Two modes:**
- **Manual** — you tap Start on each exercise when you're ready
- **Auto** — exercises and rest timers chain automatically; you just do the work

### Supporting features

Everything below exists only to make the two flows above possible or better.

| Feature | Why it exists |
|---|---|
| **Create a Route** | You need a route before you can run one |
| **Create a Plan** | You need a plan before you can execute one |
| **Exercise Library** | Add custom exercises so your plan reflects your actual workout |
| **Settings → Countdown** | Control how long the "get ready" timer runs before each exercise |
| **Settings → Rest Duration** | Control how long Auto mode rests between exercises |
| **Analytics** | Answer "am I getting faster?" after running the same route repeatedly |
| **Session History / Calendar** | See what you've done and when |
| **Plan Groups** | Organize plans when you have several (HYROX, strength, etc.) |
| **Rename / Delete / Move** | Keep your library clean as your training evolves |

---

## Color Palette

A navy-to-bright-blue spine with light-blue accents, on clean white/slate neutrals. **Always consult this before choosing any color.**

### Core brand (navy → blue)

| Hex | Role |
|---|---|
| `#1e3a8a` | Primary navy — app-icon tile, heading accents |
| `#0e1430` | Deep navy dark — hero gradient |
| `#070a18` | Deepest navy — hero gradient |
| `#15235a` | Mid navy — gradient stop |
| `#2563eb` | Primary blue — links, feature numbers, accents |

### Light blues ("surge" accents)

| Hex | Role |
|---|---|
| `#60a5fa` | Light blue — surge line, accent highlight |
| `#5a8df0` | Softer blue — dark-icon variant line |
| `#93c5fd` | Pale blue — dotted trail, secondary |
| `#bfdbfe` | Very light blue — card top-border |
| `#dbeafe` | Lightest blue tint — gradients |

### Neutrals / text

| Hex | Role |
|---|---|
| `#ffffff` | White — icon "15", text on dark |
| `#0f172a` | Ink — body text on light |
| `#c2cde4` | Light slate — tagline on dark hero |
| `#9fb0d4` | Muted slate — captions, placeholders |
| `#f5f8fd` | Soft off-white blue — alternating section backgrounds |

## Design

### Three core nouns

```
SurgeSession (a workout day — Jun 20, optionally from a Plan)
└── Session  (one exercise effort — Run 400m, Lunge 24m, 2 min Break…)

Route       (a fixed GPS loop — "Backyard 1k")
└── RouteSegment[]   (the path between turn cues, each ends with a direction)

Plan        (a reusable workout template — "HYROX Simulation")
└── PlanItem[]       (exercise type + measure + target, in order)
```

- **`Route`** — fixed GPS loop. Created once, reused. Owns its `definitionPoints` (GPS path), `segments` (turn-by-turn structure), and all `sessions` ever run on it.
- **`RouteSegment`** — one straight-line piece between turn cues. Has a target distance and an `endLabel` (`Left`, `Right`, `Turnaround`, `Straight`, or `End`) so the runner gets the right turn alert at the right cumulative distance.
- **`Session`** — one exercise effort recorded inside a SurgeSession. Carries `workoutType`, `workoutMeasure`, `targetValue`. GPS-backed sessions (runs on routes) also have a sliced GPS trace and `lapCompletedAt: [Date]`.
- **`SurgeSession`** — a day's workout container. Auto-named by time-of-day; can be created blank or instantiated from a Plan.
- **`Plan`** — a reusable workout template. A list of `PlanItem(workoutType, measure, targetValue)` entries — route-agnostic. When applied, the new SurgeSession references the Plan so its detail view can show a "Planned" checklist that ticks off as matching sessions are recorded.

### Why this split matters for HYROX

A HYROX athlete reuses the *same* 1k loop dozens of times. The question that actually matters is **"how am I improving on my loop?"** That only makes sense when sessions are grouped under a route — otherwise you just have a flat pile of unrelated recordings.

A typical HYROX training day is more than one effort — multiple runs, possibly with other exercises sandwiched in. That's why a `SurgeSession` exists above the `Session`: one workout day, many sessions inside.

## The "Fixed Track" Constraint

The product value comes from the loop being **actually fixed** across sessions — otherwise comparing times is meaningless and the app is just a worse Strava. This drives a few hard rules.

### Gated Start (20 m tolerance)

You **cannot start a session** until your GPS position is within **20 m** of the route's start coordinate.

- 20 m = 2% of a HYROX 1k loop. Loose enough to absorb GPS drift (typically 5–10 m in the open, worse near buildings); tight enough to count as "at the start".
- Before you're in range, the Start button is disabled and shows *"Walk to Start — N m"*.
- Once in range, the button turns green and reads "Start". The map's outline turns green too.
- No "start anyway" escape hatch. If GPS is genuinely broken, the right answer is to wait for a better fix, not compromise the data model.

### Auto-Stop (distance-only, per-lap)

A lap completes the moment `currentLapDistance >= route.distanceMeters`. No "return within 20 m" check — once you start at the gate, distance is what counts.

The runner is responsible for actually running the right path. The app helps with **turn cues** (next section), not policing where you end up.

### 10 m Minimum on Create

You cannot save a route shorter than 10 m. Tapping Stop below that triggers a *"Route Too Short"* alert.

### Design integrity over convenience

The obvious "Start anyway" escape hatch was **deliberately rejected**:
- If users can start anywhere, sessions on the same route are no longer comparable.
- A warning badge punts the integrity problem onto the user instead of solving it.
- The whole point of a custom track is that it's fixed.

## Turn-by-turn structure

Routes aren't single line segments — they're a sequence of straight legs separated by direction cues.

`SegmentDirection` (in `SegmentDirection.swift`):

| Case | Pad icon | Alert color | Alert title |
|---|---|---|---|
| `.straight` | `arrow.up` | green | STRAIGHT |
| `.left` | `arrow.left` | orange | TURN LEFT |
| `.right` | `arrow.right` | orange | TURN RIGHT |
| `.around` | `arrow.down` | orange | TURN AROUND |
| `.end` | `flag.checkered` | green | FINISH |

`around.rawValue = "Turnaround"` (not `"Around"`) so older routes still decode correctly.

During session recording, when `currentLapDistance` crosses an interior segment boundary, the segment's `endLabel` drives a full-screen colored overlay + a heavy-haptic burst.

## Implementation Notes

### Models (`Item.swift` + `SegmentDirection.swift`)

| Model | Key fields | Notes |
|---|---|---|
| `Route` | `name`, `createdAt`, `definitionPoints`, `segments`, `sessions` | `distanceMeters` sums segment distances (fallback: raw GPS trace). `startCoordinate` is the first point. `bestLapDuration` / `averageLapDuration` flat-map across all sessions' lap durations. |
| `RoutePoint` | timestamp, lat/lon/alt/speed/accuracy, `route` | One GPS sample in the route definition. |
| `RouteSegment` | `order`, `distanceMeters`, `endLabel: String`, `route` | `endLabel` stores a `SegmentDirection.rawValue`. |
| `Session` | `startedAt`, `endedAt`, `workoutType`, `workoutMeasure`, `targetValue`, `targetLaps`, `lapCompletedAt: [Date]`, `route?`, `surgeSession`, `points` | GPS sessions also have a route and point trace. `lapDurations` walks `lapCompletedAt`. `displayTarget` formats measure + value for UI. |
| `SessionPoint` | timestamp, lat/lon/alt/speed/accuracy, `session` | One GPS sample inside a session. |
| `SurgeSession` | `name`, `date` (start-of-day), `createdAt`, `plan`, `sessions` | `autoName(for:)` produces *"Morning · Jun 20"* etc. `totalDurationSeconds`, `totalDistanceMeters` aggregates. |
| `PlanGroup` | `name`, `createdAt`, `cardGradientIndex`, `isFavorite`, `plans` | Named container for plans. Can be empty. Plans use `.nullify` delete rule — deleting a group orphans its plans rather than deleting them. |
| `Plan` | `name`, `createdAt`, `items`, `group?`, `isFavorite`, `cardGradientIndex` | Template. `items` cascade-delete with the plan. Belongs to an optional `PlanGroup`. |
| `PlanItem` | `order`, `workoutType`, `measure`, `targetValue`, `plan` | One exercise target in a plan. Route-agnostic. |
| `CustomExercise` | `name`, `iconName`, `measures: [WorkoutMeasure]`, `sortOrder`, `createdAt` | User-defined non-GPS exercise. Supports multiple measures — gate screen shows a picker when more than one is set. Name capped at 20 chars. Icon chosen from a curated SF Symbol grid. |

Geo: `CLLocationCoordinate2D.distance(to:)` extension lives in `Item.swift`.

### Location plumbing (`LocationTracker.swift`)

A single `@Observable` class wrapping `CLLocationManager`:
- `desiredAccuracy = kCLLocationAccuracyBest`, `activityType = .fitness`, `distanceFilter = none`, `pausesLocationUpdatesAutomatically = false`.
- `start()` — continuous updates (used during recording).
- `requestSingleLocation()` — lightweight one-shot fix via `CLLocationManager.requestLocation()`. Used by the home map for initial centering. Deferred to the next `locationManagerDidChangeAuthorization(_:)` if auth is `.notDetermined`.
- Exposes `recordedLocations: [CLLocation]`, `isRecording`, `authorizationStatus`. Doesn't know anything about Routes / Sessions — views slice its output.

### Views

| View | Purpose |
|---|---|
| `ContentView` | 5-tab `TabView` shell: Routes ∙ Plan ∙ Workout (CTA) ∙ Sessions ∙ Settings. Also hosts the workout-start sheet + deferred navigation into Sessions tab. |
| `RoutesHomeView` | Map / List toggle, sort pill, rank-colored badges, cluster pins, peek sheet wiring. |
| `RoutePeekSheet` | Sheet that appears when you tap a route's pin: large preview map of the route + a [Distance \| Go \| Edit] row. |
| `EditRouteView` | Scoped to rename + delete. |
| `CreateRouteView` | Full-screen map, top-right Record/Stop pill, bottom L/⤺/R direction pad while recording. GPS warm-up overlay on appear. |
| `PlansHomeView` | Netflix-style card layout. Row 1: horizontal scroll of `PlanGroupCardView` cards. Row 2: "For You" — always-visible smart cards for Favorite Groups and Favorite Plans. Row 3: vertical list of ungrouped plans with gradient swatch + icon row. `+` menu creates a new Group or a new Plan. |
| `PlanGroupDetailView` | 2-column grid of `PlanCardView`s for all plans in the group. Heart + plus in toolbar. Empty state with "Add First Plan" CTA. |
| `CreatePlanGroupView` | Sheet: live card preview, gradient swatch picker, name field. Creates an empty `PlanGroup` immediately (plans can be added later). |
| `FavoriteGroupsView` | 2-column grid of favorited `PlanGroup`s. `ContentUnavailableView` empty state. |
| `FavoritePlansView` | 2-column grid of favorited `Plan`s. `ContentUnavailableView` empty state. |
| `CreatePlanView` | Plan identity at top: live card preview, gradient picker, name field, group chip picker. Inline exercise picker below. Reorderable + swipe-to-delete draft list. Save enabled when name + ≥1 item exist. |
| `PlanDetailView` | "Start This Plan" button (if items exist) + numbered exercise list. Name shown in nav title. Heart toggle in toolbar. Color/name/group editing deferred to Settings. |
| `SurgeSessionDetailView` | Live and past layouts. Shows elapsed timer when running. Buttons to add any exercise type. "Planned" checklist with greedy satisfaction. Sessions list with type, target, duration. |
| `ExerciseRecordingView` | Timer-based recording for all 6 exercise types. Gate → countdown (5-4-3-2-1, adjustable) → active timer → completed summary. Chip scroll for target selection. |
| `SessionRecordingView` | GPS-gated recording for route runs. Map overlay with color-coded distance status bar. Active screen: timer/distance/lap pills + direction-aware turn alerts. |
| `SessionDetailView` | Single session breakdown. |
| `SessionsHomeView` | NavigationStack wrapping the custom calendar; nav bar hidden. |
| `CalendarHomeView` | Custom month grid (active-day dots) + day's sessions grouped by ☀️ / 🌅 / 🌙 + random emoji on empty days. |
| `CalendarMonthView` | Lightweight grid replacement for `DatePicker(.graphical)` — needed because the built-in version can't show per-day markers. |
| `SettingsHomeView` | Countdown default stepper, auto-rest duration stepper, link to Exercise Library, link to Route Smoothing debug. |
| `ExerciseLibraryView` | Manage built-in exercise visibility (toggle hide/show per type) and create/edit/delete custom exercises. `ExerciseEditSheet` has name field (20 char limit), SF Symbol icon picker, and multi-select measure checkboxes. |

### Tab bar

`ContentView` is a `TabView` with five items:

```
Routes | Plan | ⚡ (Surge / Surging) | Sessions | Settings
```

- The middle tab is action-only. Icon is a UIKit-bridged `bolt.fill` rendered with `withTintColor(.systemBlue, renderingMode: .alwaysOriginal)` so the system doesn't re-tint it grey.
- Label switches between **"Surge"** (no active workout) and **"Surging"** (an unexpired surge session exists), driven by `allSurgeSessions.contains { $0.isCurrent }`.
- Tap behavior: if a current surge session exists → jump to its detail in the Sessions tab. Otherwise → bounce to the Routes tab so the user can pick a route.
- The `\.startPlan` environment closure is injected on `TabView` so `PlanDetailView` can kick off a workout (create-or-attach to current, then jump to detail) without knowing about the tab structure.
- Routes and Plan tabs each have their own NavigationStack + create-sheet states.

### Sheet → navigation handoff

SwiftUI doesn't reliably push a `NavigationStack` destination from inside a sheet button. The fix used throughout (`RoutesHomeView`, `RouteDetailView`, `ContentView`, etc.): on button tap, **store a pending value + dismiss the sheet**, then the sheet's `onDismiss:` reads the pending value and performs the navigation. This avoids the race.

### iOS configuration

Requires this Info.plist key on the app target (set via *Target → Info → Custom iOS Target Properties*):

- **`NSLocationWhenInUseUsageDescription`** — *"surge15 needs your location to record your run."* (or similar)

Without this, `requestWhenInUseAuthorization()` is a no-op and the app silently does nothing when the user taps Start.

## Iteration Log

### Iteration 1 — minimal end-to-end recording (✅ shipped)
Single start/stop button. Real-time location capture. Save with a name. Listed on the home screen. No Route/Session split.

### Iteration 2 — Route/Session split + fixed-track constraints (✅ shipped)
Separated `Route` and `Session`. Gated start (20 m tolerance). Auto-stop at ≥80% loop + within 20 m of start. 10 m minimum on create. "At Start" / "Walk to Start" pre-session UI.

### Iteration 3 — Map-based start gate (✅ shipped)
`SessionRecordingView` shows a MapKit map with the route polyline + a filled green start-tolerance circle (`MapCircle`). User location is the standard `UserAnnotation()` dot. Map's rounded border turns green when in the tolerance.

### Iteration 4 — Multi-lap sessions (✅ shipped)
`Session.targetLaps` + `lapCompletedAt: [Date]`. Pre-session lap picker. Active UI shows current lap time, distance left in lap, total elapsed, and a strip of completed-lap pills. `Route.bestLapDuration` / `averageLapDuration` flat-map across all laps so a 5-lap session contributes 5 data points.

### Iteration 5 — Segments + turnaround alerts (✅ shipped)
`RouteSegment` model. Marking turnarounds during creation produces interior segment boundaries. During a session, crossing a boundary fires a full-screen orange overlay + heavy haptic burst. Auto-stop dropped the "back within 20 m" check (distance-only, per lap).

### Iteration 6 — Map-based home screen (✅ shipped)
Home is a `Map` with one start-flag pin per route. Tapping opens `RoutePeekSheet`. `EditRouteView` (rename + delete). Toolbar toggle between map and list. Empty state with a "Create Route" CTA. Black overlay + "Switch to List View" when location is denied.

### Iteration 7 — Pin clustering + sortable list (✅ shipped)
Routes within 100 m of each other collapse into a single cluster pin (with the count). Tapping opens `ClusterSheet`. List view gains a sort pill (Distance From You / Most Frequently Used / Lap Distance). Each row gets a 64×48 colored badge whose color is determined by tie-aware ranking.

### Iteration 8 — Surge Sessions + calendar (✅ shipped)
`SurgeSession` (day container) + `Session.surgeSession` relationship. Required-attachment flow when starting a session from a route. New Calendar mode in the home toolbar.

### Iteration 9 — TabView + tie-safe badges + name truncation (✅ shipped)
Three-tab `TabView` shell with a center "Create" CTA. Tie-aware badge colors (three 1× routes all render green). Route names in compact rows clamp to 16 characters.

### Iteration 10 — Plan + Settings tabs + Workout CTA flow (✅ shipped)
Expanded to 5 tabs: Routes | Plan | + | Sessions | Settings. `Plan` + `PlanItem` models for reusable templates. The "+" became "Workout" — opens `WorkoutStarterSheet` with three sections (plans, today's sessions, new blank). Apply-plan creates a `SurgeSession` with the plan's name; its detail view shows a "Planned" checklist that satisfies greedily against recorded sessions.

### Iteration 11 — Custom calendar + emoji fallback (✅ shipped)
Replaced `DatePicker(.graphical)` with a custom `CalendarMonthView`. Active days (any day with a surge session) get a small green dot under the number. Empty days show a stable random emoji (seeded by day-since-epoch) instead of "No surge sessions on this day." Day's sessions are grouped into ☀️ / 🌅 / 🌙 sections by hour.

### Iteration 12 — Visual & flow tweaks (✅ shipped)
A bundle of UX polish:
- `+` button on Routes/Plan goes **blue** (matching the Workout CTA) when its tab is in the empty-but-actionable state.
- On the Plans tab when there are no routes, the `+` greys out and tapping it yellow-highlights *"Create a route first."*
- Routes/Plan/Settings nav titles removed (`navigationBarTitleDisplayMode(.inline)` or hidden nav bar).
- Cluster + peek sheet: bigger route preview map, [Distance | Go | Edit] action row, equal top/bottom padding.
- Glowing button experiments were tried + reverted in favor of plain blue.

### Iteration 13 — Full-screen CreateRouteView + GPS warm-up (✅ shipped)
- The Create-Route screen is now a full-screen map with overlays.
- Record/Stop pill in the top-right toolbar (red capsule).
- Direction pad floats over the bottom of the map while recording.
- Distance pill overlays the top-left of the map.
- On view appear, a 2.5 s **"Acquiring GPS Location"** overlay covers the screen so the first jittery GPS fixes are discarded before the user can tap Record.
- Stripped instructions, "minimum 10 m" indicator, points-captured counter, status text, and the always-on segment summary.

### Iteration 14 — Directional controller (D-pad) (✅ shipped)
The single Mark Turnaround button became a controller: Left / Around / Right. Forward is implied (no Up button — if you don't tap, the path continues straight). New `SegmentDirection` enum drives:
- The D-pad button icons + the pin/pill glyphs in `CreateRouteView`.
- The full-screen in-session alert (color, icon, title).
- Per-segment `RouteSegment.endLabel` storage.

### Iteration 15 — Sessions list polish (✅ shipped)
On the Calendar tab, when a day has sessions:
- Top "Friday, June 20, 2026" header removed (redundant with the calendar above).
- Sessions grouped into ☀️ Day / 🌅 Afternoon / 🌙 Night sections, with the emoji *as* the section header.
- Row shows start time as headline + session count + total duration as the subhead. Date-suffixed names like *"Morning · Jun 20"* are stripped.

### Iteration 19 — Six exercise types + inline plan builder (✅ shipped)

**Six exercise types.** The `WorkoutItemType` enum now has six cases, each with its own measure constraints:

| Case | Display | Measures |
|---|---|---|
| `.run` | Run | meters, laps |
| `.lunge` | Lunge | meters, yards, reps |
| `.burpeeBroadJump` | Burpee Broad Jump | meters, yards, reps |
| `.row` | Row | meters |
| `.wallBall` | Wall Balls | reps |
| `.rest` | Break | minutes |

Each type also has a `shortName` ("BBJ", "W.Ball", "Break", etc.) used in compact chip pickers and plan summaries.

**New `WorkoutMeasure` cases**: `.yards` (same presets as meters, label `yd`) and `.minutes` (presets: 30s, 1m … 20m, labels like "30s" / "2m").

**`CreatePlanView` — inline builder.** The separate `AddPlanItemView` sheet was eliminated entirely. The plan builder is now all on one screen:
- **Type chip scroll**: horizontal scrolling chips with icon + short name — one compact row, scales to any number of types.
- **Measure segmented control**: appears only when the selected type has more than one measure option.
- **Target chip scroll**: same right-edge fade pattern as the type chips.
- **"Add to Plan" button**: appends the current selection to a growing list below.
- Plan items are reorderable + swipe-to-delete. Save prompts for a name via alert.
- `AddPlanItemView.swift` deleted.

**`ExerciseRecordingView` updated** to support all 6 types:
- Minute presets added; chip labels show "30s" / "2m" format.
- Row defaults to 1000m; Break defaults to 2 minutes.
- All `currentPresets` and `onChange` handlers cover every `WorkoutMeasure` case exhaustively.

### Iteration 18 — Exercise types + unified UI patterns (✅ shipped)

**Three exercise types everywhere.** Runs, Lunges, and Burpee Broad Jumps are first-class citizens in both Surge Sessions and Plans.

**`PlanItem` model redesigned** (breaking change — delete + reinstall to migrate):
- Removed: `route`, `targetLaps`
- Added: `workoutType: WorkoutItemType`, `measure: WorkoutMeasure`, `targetValue: Double`
- Plans are now route-agnostic. A plan is just a list of exercise targets (e.g. "Run 400m, Lunge 24m, BBJ 10 reps").

**`Session` model extended** with `workoutType`, `workoutMeasure`, `targetValue`, `displayTarget` to track what was actually done.

**`ExerciseRecordingView`** (new file) — timer-based recording for any exercise type:
- Three states: gate (pick measure + target) → countdown overlay (5-4-3-2-1, adjustable) → active timer → completed summary.
- Horizontal chip scroll for target selection with a right-edge fade mask.
- Countdown overlay has +/- buttons to adjust and a cancel button.
- Used for all exercise types (no GPS — just time the effort).

**`CreatePlanView`** — plan name moved from form field to save-time alert.

**Gate screen redesigned** (`SessionRecordingView`):
- Lap/meters picker **moved from gate screen → route popup** (`RoutePeekSheet`). Gate screen is now GPS-only.
- Full-width colored status bar replaces the old "Walk to Start" button: red when far, orange when close, green when in range. Shows descriptive text like *"You are too far away! Walk 23m closer to start."*

**Route popup flows are now identical**:
- Map: tap pin → overlay popup → Go → record.
- List: tap row → same overlay popup → Go → record.
- Previously the list bypassed the popup entirely (direct-to-record). Fixed by wiring the list row's tap to `peekRoute = route` instead of `navigatingToRecording = true`.

### Iteration 17 — "Current Surge Session" + Surge tab (✅ shipped)

The biggest mental-model change since iteration 8: **surge sessions can no longer be created manually**. They're a consequence of starting a workout, not a thing you set up.

**The new rule**: at any moment there's at most one *current* surge session. It expires **1 hour after its last activity** (where activity = the surge session's `createdAt` or the start of its most recent attached `Session`, whichever is later).

**New model helpers** (`Item.swift`):
- `SurgeSession.lastActivityAt: Date`
- `SurgeSession.isCurrent: Bool` — true while inside the 1-hour window.
- `SurgeSession.current(in: ModelContext)` — fetches the most recent unexpired surge session, or nil.
- `SurgeSession.currentOrNew(in: ModelContext)` — get-or-create. Inserts a fresh auto-named surge session if no one is current.
- `SurgeSession.currentSurgeExpiryInterval: TimeInterval = 3600`.

**Go flow on the Routes tab** simplified again:
- Old: Go → surge picker → record. (Iteration 16's surge picker.)
- New: Go → `SurgeSession.currentOrNew(in:)` → record. **No picker.**
- Map peek's Go button and list-row tap both call the same helper, then push `SessionRecordingView` via the same `.navigationDestination(item: $goSurge)`.
- `showingGoSurgePicker` + `pendingGoSurge` states deleted from `RoutesHomeView`.

**Middle tab renamed Workout → Surge** (option B from clarifying questions):
- Icon: blue `bolt.fill` (UIImage-bridged with `.alwaysOriginal` rendering — same trick the `+` used).
- Label: **"Surge"** normally, **"Surging"** when an unexpired surge session exists. Computed reactively from the `@Query` on `SurgeSession`.
- Tap behavior: if a current surge session exists → jump to its detail (Sessions tab + path reset). Otherwise → bounce to the Routes tab so the user can pick a route.

**Plans → workout** flow:
- Plan creation/editing is unchanged (`PlansHomeView`, `CreatePlanView`, `PlanDetailView`).
- `PlanDetailView` gains a prominent **"Start This Plan"** row at the top (blue-tinted background, `bolt.fill` icon).
- Tapping it calls a closure injected via SwiftUI environment value (`\.startPlan`). Logic:
  - If a current surge session exists with no plan attached → attach this plan + rename the surge after it. Use the current.
  - If a current surge session exists with a plan already attached → reuse it as-is (don't overwrite).
  - Otherwise → create a new surge session named after the plan, with the plan attached.
- After resolution, push the surge session's detail view in the Sessions tab.

**Files deleted** (dead code after this iteration):
- `SurgeSessionPickerSheet.swift` — picker is gone.
- `WorkoutStarterSheet.swift` — the middle tab no longer presents a sheet.
- `RouteDetailView.swift` — unreachable since iteration 16; no path back to it now that the Go flow doesn't push it.

**Edge cases**:
- An "empty" surge session (created by Start-Plan but no session ever recorded) still expires 1 hour after its `createdAt`. It will sit in the calendar as a 0-session row until the user manually deletes it from `SurgeSessionDetailView`.
- Tab label reactivity uses `Date()` snapshots on each render. A surge session that just expired between renders won't auto-relabel — but it will the next time the view body re-evaluates (tab switch, query change, etc.). Good enough without a background timer.

### Iteration 16 — "Go = Start" everywhere on Routes tab (✅ shipped)

Both ways of selecting a route on the Routes tab now drop straight into the surge-session picker and on into recording — no more "Start Session" double-tap.

**Map flow** (peek sheet → Go):
- Previously: peek's *Go* → push `RouteDetailView` → tap *"Start Session"* → surge picker → record. **5 taps.**
- Now: peek's *Go* → surge picker → record. **3 taps.**

**List flow** (row tap):
- Previously: tap row → push `RouteDetailView` → tap *"Start Session"* → surge picker → record.
- Now: tap row → surge picker → record. Exact same path the map's Go button uses.

**Implementation in `RoutesHomeView`**:
- Renamed `pendingOpen: Route?` → `goRoute: Route?` (semantic: "user said Go on this route").
- Added `showingGoSurgePicker`, `pendingGoSurge`, `goSurge` to plumb the picker → recording handoff using the same deferred-dismiss pattern as the rest of the app.
- Peek sheet's `onUse` callback now sets `goRoute` instead of triggering a detail-view push.
- `handlePeekDismiss()` shows the surge picker when `goRoute` is set.
- New `handleGoSurgeDismiss()`: if a surge was picked → set `goSurge` (fires `.navigationDestination(item:)`); if canceled → clear `goRoute`.
- List rows changed from `NavigationLink(value: route)` to a `Button` that sets `goRoute` and `showingGoSurgePicker = true` directly (no peek sheet in between).

**Side effect — `RouteDetailView` is currently unreachable**. The per-route history page (best lap, average lap, sessions list, segments) is not on any tap path right now. The `.navigationDestination(for: Route.self)` registration is dead code until a new entry point is added (likely a "Stats" tile on the peek sheet or a "Past Sessions" link inside `EditRouteView`).

### Iteration 20 — Plan Groups + Netflix-style Plans tab (✅ shipped)

**`PlanGroup` model** added as a first-class SwiftData entity. Groups exist independently of plans — you can create an empty group and add plans to it later. The `plans` relationship uses `.nullify` so deleting a group orphans its plans rather than deleting them.

**`PlansHomeView` redesigned** with a three-row layout:
- **Row 1 — Groups**: horizontal scroll of gradient `PlanGroupCardView` cards (130×130). Tapping navigates into the group.
- **Row 2 — For You**: always-present pair of full-width smart cards — "Favorite Groups" (links to `FavoriteGroupsView`) and "Favorite Plans" (links to `FavoritePlansView`). Visible even before any favorites exist.
- **Row 3 — Ungrouped**: vertical list of plans not assigned to any group, each with a gradient swatch and exercise icon row.
- `+` toolbar menu: "New Group" → `CreatePlanGroupView` sheet, "New Plan" → `CreatePlanView` sheet.
- Nav title removed to reclaim vertical space.

**New files:**
- `CreatePlanGroupView.swift` — sheet with live gradient card preview + name field. Creates the group immediately so plans can be added on a future visit.
- `PlanGroupDetailView.swift` — 2-column `LazyVGrid` of plan cards, heart + plus in toolbar, empty-group CTA. No editable header card; name/color editing is deferred to Settings.
- `FavoriteGroupsView` and `FavoritePlansView` — defined at the bottom of `PlansHomeView.swift`. Each is a 2-column grid filtered by `isFavorite`, with a `ContentUnavailableView` empty state.

**`CreatePlanView` updated**: plan identity section (live card preview, gradient picker, name field, group chip picker) moved to the top. Group chip picker shows "None" + all existing groups with gradient dot swatches. Preset group wired via `.onAppear`.

**`PlanDetailView` simplified**: hero card preview removed, identity/color/group editor removed, delete button removed. Now shows only the "Start This Plan" CTA and the exercise list. Editing and deletion deferred to Settings.

**Shared components** defined in `PlansHomeView.swift`:
- `PlanGradient` struct + `planGradients` array (12 gradients: Ocean, Forest, Ember, Rose, Sunrise, Sky, Cherry, Midnight, Lime, Neon, Citrus, Galaxy).
- `PlanCardView` — 170×120 pt card (or featured full-width×190) with gradient background + exercise icon bubbles.
- `PlanGroupCardView` — 130×130 pt card with folder icon + plan count.
- `GradientPickerView` — horizontal row of 44 pt circle swatches with checkmark on the selected one.
- `SmartGroupCardView` — full-width card with fixed gradient for the "For You" row.
- `SmartGroupDestination` enum (`.favoriteGroups`, `.favoritePlans`) used with `navigationDestination(for:)`.

**`Session.workoutType` made optional** (`WorkoutItemType?`). Old database rows that had NULL in this column were causing a SwiftData cast crash. Making the property optional fixes it without requiring a migration.

### Iteration 21 — Unified workout timeline + plan-driven action bar (✅ shipped)

A top-to-bottom redesign of `SurgeSessionDetailView` and related surfaces to make the live workout flow feel intentional and controllable.

**Live nav title — elapsed timer.**
The navigation bar title now shows the running elapsed time (`00:00`) instead of the surge session name. Color is reactive: white while active, orange while paused, and flashes green for 1 s on resume. Implemented via a `.principal` `ToolbarItem` with a computed `titleColor` and a `flashingGreen` `@State` toggle.

**Unified timeline.**
Ad-hoc recorded sessions are no longer shown in a separate "Additional" section below the plan checklist. They're interleaved chronologically in a single timeline alongside plan items and queued exercises, using a private `SurgeTimelineEntry` enum with three cases: `.planItem`, `.adHocSession`, `.pending`.

**Exercise queue instead of immediate start.**
Tapping `+` to add an exercise now opens `ExerciseConfigSheet` — a modal where you pick measure + target — then appends the exercise to the end of the future timeline as a `PendingExercise`. Nothing starts until you press Start. This makes queued exercises first-class citizens you can reorder before committing.

**Reorder sheet.**
When there are any future items (plan or queued), an "↕ Reorder" button appears in the workout timeline section header. It opens `ReorderSheet` — a `List` in always-active edit mode that lets you drag reorder the full future queue (plan items + pending exercises interleaved). Items already completed or in progress are shown as frozen (non-draggable). The `applyReorder` function splits the result back into `timelineOrder` and `pendingAdHocItems`. The sheet always opens at full height (`.large` detent only) to prevent the last row from colliding with the sheet's bottom edge.

**Redesigned action bar.**
The five-button bar at the bottom now reads left-to-right: **Back · Skip · Start · Pause↔Go · Stop**.
- **Back** — undoes the last skip (plan item or queued exercise).
- **Skip** — marks the current item (plan or pending) as skipped; it remains visible in the timeline as italic + "Skipped" with a forward-arrow circle icon.
- **Start** (center, 50 pt green `play.circle.fill`) — launches the current plan item or the first non-skipped queued exercise. Disabled when nothing is actionable.
- **Pause / Go** — toggles pause state; nav title turns orange while paused, flashes green on resume.
- **Stop** — confirms ending the workout.

**Skip works for queued exercises.**
Previously Skip was disabled when no plan item was current. Now it also skips the first non-skipped queued exercise. Skipped pending exercises stay visible in the timeline (matching plan item skipped style) and Back restores them in reverse order. Implemented via `skippedPendingIDs: [UUID]` alongside the existing `skippedItems: [PersistentIdentifier]` for plan items.

**Gate bypass for plan items.**
`ExerciseRecordingView` now accepts optional `measure` and `targetValue` init parameters. When both are provided (as they always are when launching from a plan item), `skipGate = true` and the view auto-starts the countdown on `.onAppear`, skipping the measure/target config screen entirely.

**PlanDetailView — vertical timeline + Start toolbar button.**
The exercise card list in `PlanDetailView` was replaced with a connected vertical timeline (`planTimelineRow`) matching the style of the workout timeline. The heart toggle in the toolbar was removed; a **Start** button (disabled until a route is selected) takes its place. The "Start This Plan" bottom CTA was removed.

**Heart moved to PlanCardView.**
The favorite heart indicator was moved from the `PlanDetailView` toolbar into the top-right corner of `PlanCardView` (the gradient card), shown as a small `heart.fill` overlay on top of the card clip shape.

**Completed ad-hoc sessions — green checkmark circle.**
The `+` icon on ad-hoc session rows in the timeline was changed to a green `checkmark.circle.fill` to visually distinguish "done" from "add".

### Iteration 22 — Custom exercise library, plan flow polish, analytics redesign, group/plan management (✅ shipped)

**Custom Exercise Library** (`ExerciseLibraryView.swift`, `Item.swift`)
- New `CustomExercise` SwiftData model: `name` (20 char limit), `iconName`, `measures: [WorkoutMeasure]`, `sortOrder`.
- **Multi-select measurements**: when creating or editing a custom exercise, tap any combination of Reps / Meters / Yards / Minutes. At least one must remain selected. When multiple are chosen, the recording gate screen shows a segmented measure picker identical to built-in exercises like Lunge.
- **Hide/show built-ins**: toggle switches per exercise type (all except Run). Toggled types are stored as a comma-separated `@AppStorage` string and filtered out of the exercise picker and workout queue.
- Custom exercises appear in the "Add Exercise" sheet under a "My Exercises" section and can be added to the pending queue or used ad-hoc.
- `Session` model extended with `customExerciseName: String?` and `customExerciseIcon: String?` so custom sessions display correctly in the timeline history. Computed `exerciseDisplayName` and `exerciseSystemImage` fall back gracefully.
- `ExerciseRecordingView` given a second init path that accepts `measures: [WorkoutMeasure]` instead of a single `WorkoutItemType`.
- `SurgeSessionDetailView` updated: `PendingExercise` carries `availableMeasures: [WorkoutMeasure]` for custom exercises; `CustomRecordingRequest` updated to `measures: [WorkoutMeasure]`.

**Plan session flow polish** (`SurgeSessionDetailView.swift`, `SessionRecordingView.swift`, `ExerciseRecordingView.swift`)
- **Skip GPS run config page**: when a plan item is a Run with a known target, `directRunDestination` is set directly, bypassing `RouteRunSetupView` entirely. Ad-hoc runs still show the config screen.
- **Skip all exercise summary screens**: after any exercise (GPS run or non-GPS) completes inside a surge session, the view dismisses straight back to the timeline instead of showing the "Session Saved" / "Back to Workout" summary. Summary screen only appears for standalone exercises outside a surge session.
- **Auto mode UX overhaul**: replaced segmented Picker with a custom two-chip toggle. Manual chip is white; Auto chip is orange with a bolt icon. Tapping Auto when not enabled shows a confirmation alert ("Switching to Auto Mode will start the first workout…"). On confirm, the first exercise starts immediately.
- **Auto mode defaults to Manual**: changed `@AppStorage` → `@State` so auto mode resets to off each time a surge session is opened. Previously it persisted across sessions.
- **Workout Complete overlay**: after the last exercise in auto mode, instead of starting another countdown timer, a full-screen overlay appears with falling confetti (60 animated pieces, staggered delays, random colors), a trophy icon, "Workout Complete!" text, and a tap-to-dismiss. The workout is automatically paused. `handleAutoModeExerciseComplete()` checks whether any future items remain before deciding between auto-rest and the celebration.

**Analytics redesign** (`AnalyticsView.swift`)
- **Headline stat above each chart**: frequency card shows total workout count (or selected bar's count while dragging); pace card shows average pace with best pace in the top-right corner.
- **Tap / drag to inspect**: `chartXSelection(value:)` on both charts. Touching a bar or line point updates the headline in real time. Unselected bars dim to 20% opacity; a dashed `RuleMark` appears at the selected position.
- **Y-axis hidden on frequency chart**: the bar chart needs no y-axis when the count is shown in the headline.
- **Pace y-axis simplified**: only 2 labels (min and max in range, formatted as `m:ss`) instead of a dense tick list.
- **Taller frames**: charts grew from 130 pt to 170 pt.
- **Selection resets on range change**: switching 7D / 30D / 3M / All clears any active inspection.
- **Card shell refactor**: `analyticsCard(title:subtitle:content:)` replaced with `cardShell { }` — the headline stat is now inlined inside each card instead of being a separate section header, matching how fitness apps like Strava present chart data.

**Plan & group management** (`PlanDetailView.swift`, `PlanGroupDetailView.swift`)
- **Group rename & delete**: `PlanGroupDetailView` toolbar gains a `…` menu — "Rename Group" (alert with text field) and "Delete Group" (confirmation alert; plans become ungrouped, not deleted, via the existing `.nullify` delete rule).
- **Plan rename & delete**: `PlanDetailView` toolbar gains a `…` menu — "Rename Plan" (alert with text field) and "Delete Plan" (confirmation alert; plan and all its `PlanItem`s are permanently removed).
- **Move plan to group**: "Add to Group" / "Move to Group" opens `MovePlanToGroupSheet` — a list of all groups with gradient swatches and a checkmark on the current group. Tapping any group moves the plan instantly. "Remove from Group" appears when the plan already belongs to one.

### Iteration 23 — UI consistency polish, brand color system, surge intent redesign (✅ shipped)

A wide sweep of visual consistency and UX clarity changes across the Plans, Routes, and Surge tabs.

**Run count badges replace gradient swatches in plan rows** (`PlansHomeView.swift`)
- Every plan row on the Plans tab (All Plans section, Favorite Plans, Group detail) now shows a rounded-rectangle badge containing the number of times the plan has been executed, instead of a colored gradient swatch.
- Badge uses brand light-blue background and brand primary-blue number text to match the app's color palette.
- Plans are sorted by `surgeSessions.count` descending — most-used plans rise to the top.
- Required adding `@Relationship(inverse: \SurgeSession.plan) var surgeSessions: [SurgeSession] = []` to the `Plan` model in `Item.swift`. No migration needed — `SurgeSession.plan` already existed; this just adds the inverse accessor.

**"All Plans" shows every plan** (`PlansHomeView.swift`)
- The section formerly titled "Ungrouped" was renamed to "All Plans" and now shows every plan regardless of group membership.
- Users can use it as a flat view of all plans sorted by run count without needing to dig into groups.

**"Change Color" in group context menu** (`PlansHomeView.swift`)
- Long-pressing a group card now includes a "Change Color" option alongside "Rename Group" and "Delete Group".
- Opens a new `GroupColorPickerSheet` with a live card preview at the top and the full gradient picker below — same picker used in `CreatePlanGroupView`.

**`PlanGroupDetailView` converted to row list** (`PlanGroupDetailView.swift`)
- Replaced the 2-column `LazyVGrid` of plan cards with a vertical row list styled identically to the All Plans section.
- Each row has: run count badge · plan name · exercise count · heart indicator · chevron · inset divider.
- Row long-press context menu: Rename Plan, Move to Group, Delete Plan.
- Fixed a safe-area overlap bug: content was scrolling behind the navigation bar because `.background(pageBackground.ignoresSafeArea())` was applied directly to the `ScrollView`, confusing SwiftUI's content inset calculation. Fixed by moving the background into a `ZStack` sibling beneath the `ScrollView`.

**Heart toggle restored to `PlanDetailView` toolbar** (`PlanDetailView.swift`)
- The favorite heart button (removed in an earlier iteration) was added back next to the Start button in the navigation toolbar.
- Tapping toggles `plan.isFavorite` and updates the icon and color (filled red when favorited).

**Route session count badge** (`ContentView.swift`)
- Routes list rows now show a rounded-rectangle badge with the number of times the route has been run, replacing the generic running-figure SF Symbol icon that was the same for every route.
- Same badge visual treatment as plan rows (brand palette).

**`FavoritePlansView` redesigned to row list** (`PlansHomeView.swift`)
- Replaced the 2-column plan card grid with a vertical row list using the same style as All Plans.
- Sorted by run count descending. Always-visible heart indicator. Context menu with Rename Plan, Move to Group, Delete Plan (with confirmation).

**`FavoriteGroupsView` redesigned to row list** (`PlansHomeView.swift`)
- Replaced the 2-column group card grid with a vertical row list.
- Each row shows the group's gradient swatch (28×28 rounded rectangle), group name, plan count, and chevron.
- Context menu with Rename Group, Change Color, Delete Group (with confirmation).

**Delete confirmations everywhere**
- Groups, plans, and routes all require an alert confirmation before deletion. No item can be deleted with a single tap.
- Implemented via optional state bindings: `deletingGroup: PlanGroup?`, `deletingPlan: Plan?`, `deletingRoute: Route?`. Alert binding uses `Binding(get: { state != nil }, set: { if !$0 { state = nil } })` pattern.

**`SurgeIntentView` complete redesign** (`ContentView.swift`)
- Changed from `.fullScreenCover` to `.sheet` so the view can be dismissed by dragging down, matching every other sheet in the app.
- Fixed height: `presentationDetents([.height(320)])` — no wasted space, no medium-detent dead zone.
- Background color: `presentationBackground(pageBackground)` colors the entire sheet presentation (not just the view frame) so dark mode shows a solid navy behind both tiles, not a black box.
- Brand gradients: "Run a Route" tile uses `#1e3a8a → #2563eb`; "Execute a Plan" tile uses `#15235a → #60a5fa`. Previous versions had purple/green gradients that violated the color palette.
- Count capsule badges in the top-right corner of each tile: number of routes or plans saved. Shows an orange `exclamationmark.triangle.fill` when count is 0.
- Orange empty-nudge strip below each tile when count is 0 ("Create a route first to run one" / "Create a plan first to execute one").
- 65 funny motivational quotes displayed above the two tiles. A new random quote is picked on each `.onAppear` (not on init — SwiftUI preserves `@State` across sheet dismissals, so `.onAppear` is required to re-randomize).

**Calendar future-date quotes** (`ContentView.swift` / `CalendarHomeView`)
- Tapping a future day on the calendar now shows a playful "you're planning ahead" quote instead of a rest-day quote.
- 15 quotes with a light, forward-looking tone (e.g. "Woah, you're already planning your workout for this day.").
- Implemented via an `isFuture: Bool` computed property on the selected date; `quoteForSelectedDate` checks this before falling back to `restDayQuotes`.

## Possible next steps

- **Break countdown in `ExerciseRecordingView`** — currently a Break records elapsed time like any other exercise. It should count *down* from the target instead of counting up, and auto-complete when it reaches zero.
- **Plan editing**: `PlanDetailView` only supports rename + delete. Editing individual plan items (reorder, change target, remove) needs to be added — could reuse the same inline picker from `CreatePlanView`.
- **GPS-backed run option in Surge Session** — currently "Add Exercise → Run" in a surge session goes to `ExerciseRecordingView` (time only, no GPS). Could offer the option to link to a saved route for GPS-tracked laps.
- **Plan satisfaction for reps/minutes** — the greedy satisfaction check in `SurgeSessionDetailView` only auto-ticks Run items (meters/laps). Reps and timed exercises can't be auto-checked yet.
- **Real Settings**: measurement units (m/km ↔ miles / yards), backups (Files / iCloud export), screen-on lock during recording.
- **Persist sort preference** across launches (currently `RouteSort` is view-local `@State`).
- **Zoom-aware clustering threshold** — currently a flat 100 m real-world distance regardless of zoom level.
- **"Fit all routes" button** that adjusts the home map to a region encompassing every route.
- **Lap-complete haptic + overlay** mirroring the turn alert (different color, "LAP DONE" text).
- **Custom segment labels** — let the user name turnarounds during creation (e.g. "Bench", "Tree", "Lifeguard stand").
- **Audible cues** in addition to haptic + visual (system sound or spoken "turn left").
- **Map during the active session** — show the user's live trace as they run the loop.
- **Splits / per-segment pace** within each lap.
- **Per-session comparison view** ("today vs PB").
- **Background location updates** so the screen can be locked during a run (requires `UIBackgroundModes = location` + `allowsBackgroundLocationUpdates = true` + a `CLBackgroundActivitySession`).

## Project Structure

- `surge15/` — app source (SwiftUI)
- `surge15Tests/` — unit tests (Swift Testing framework)
- `surge15UITests/` — UI tests (XCUIAutomation)
