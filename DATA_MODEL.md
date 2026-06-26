# surge15 — Data Model

## Entity Overview

```
PlanGroup
└── Plan[]             (nullify on group delete — plans become ungrouped)
    └── PlanItem[]     (cascade delete with plan)

Route
├── RoutePoint[]       (cascade — GPS definition of the loop)
├── RouteSegment[]     (cascade — turn-by-turn structure)
└── Session[]          (cascade — every run ever done on this route)

SurgeSession           (a single workout day / envelope)
├── Plan?              (optional — which template this session uses)
├── Route?             (optional — set on first GPS run)
└── Session[]          (nullify — individual exercise efforts)
    └── SessionPoint[] (cascade — GPS trace for that effort)

CustomExercise         (user-defined non-GPS exercise, standalone)
```

---

## SwiftData Models

### `Route`

A fixed GPS loop. Created once, reused across many sessions.

| Property | Type | Notes |
|---|---|---|
| `name` | `String` | User-given label |
| `createdAt` | `Date` | |
| `isFavorite` | `Bool` | default `false` |
| `definitionPoints` | `[RoutePoint]` | Cascade delete, inverse `RoutePoint.route` |
| `segments` | `[RouteSegment]` | Cascade delete, inverse `RouteSegment.route` |
| `sessions` | `[Session]` | Cascade delete, inverse `Session.route` |

**Computed:**

| Property | Returns | Notes |
|---|---|---|
| `distanceMeters` | `Double` | Sum of segment distances; falls back to raw GPS trace length for legacy single-segment routes |
| `startCoordinate` | `CLLocationCoordinate2D?` | First `sortedDefinitionPoints` point |
| `endCoordinate` | `CLLocationCoordinate2D?` | Last `sortedDefinitionPoints` point |
| `segmentEndDistances` | `[Double]` | Cumulative distance at each segment boundary; crossing an interior one triggers a turn alert |
| `bestLapDuration` | `TimeInterval?` | Min across all laps in all sessions |
| `averageLapDuration` | `TimeInterval?` | Mean across all laps in all sessions |
| `sortedDefinitionPoints` | `[RoutePoint]` | Sorted by `timestamp` |
| `sortedSessions` | `[Session]` | Sorted by `startedAt` descending |
| `sortedSegments` | `[RouteSegment]` | Sorted by `order` |

---

### `RoutePoint`

One GPS sample that defines a route's shape.

| Property | Type |
|---|---|
| `timestamp` | `Date` |
| `latitude` | `Double` |
| `longitude` | `Double` |
| `altitude` | `Double` |
| `speed` | `Double` |
| `horizontalAccuracy` | `Double` |
| `route` | `Route?` |

**Computed:** `coordinate: CLLocationCoordinate2D`

---

### `RouteSegment`

One straight leg between two direction cues.

| Property | Type | Notes |
|---|---|---|
| `order` | `Int` | Position in the sequence |
| `distanceMeters` | `Double` | Length of this leg |
| `endLabel` | `String` | Stores a `SegmentDirection.rawValue` — drives the turn-alert overlay |
| `route` | `Route?` | |

---

### `Session`

One exercise effort recorded inside a `SurgeSession`. GPS-backed sessions (route runs) also carry a location trace.

| Property | Type | Notes |
|---|---|---|
| `startedAt` | `Date` | |
| `endedAt` | `Date?` | nil while in progress |
| `targetLaps` | `Int` | default `1` |
| `lapCompletedAt` | `[Date]` | Timestamps of each lap completion, in order |
| `route` | `Route?` | Set for GPS runs; nil for exercise sessions |
| `surgeSession` | `SurgeSession?` | Parent envelope |
| `points` | `[SessionPoint]` | Cascade delete, inverse `SessionPoint.session` |
| `workoutType` | `WorkoutItemType?` | Optional for backwards compatibility with older rows |
| `workoutMeasure` | `WorkoutMeasure` | default `.laps` |
| `targetValue` | `Double` | default `1.0` |
| `customExerciseName` | `String?` | Set when session came from a `CustomExercise` |
| `customExerciseIcon` | `String?` | SF Symbol name for the custom exercise |

**Computed:**

| Property | Returns | Notes |
|---|---|---|
| `durationSeconds` | `TimeInterval?` | `endedAt - startedAt`; nil while in progress |
| `distanceMeters` | `Double` | Summed GPS trace length |
| `paceSecondsPerKilometer` | `Double?` | `duration / (distanceMeters / 1000)`; nil if no distance |
| `lapDurations` | `[TimeInterval]` | Walks `lapCompletedAt`; falls back to one entry = total duration for legacy sessions |
| `displayTarget` | `String` | Formatted `workoutMeasure.formatted(targetValue)` |
| `exerciseDisplayName` | `String` | `workoutType?.displayName ?? customExerciseName ?? "Exercise"` |
| `exerciseSystemImage` | `String` | `workoutType?.systemImage ?? customExerciseIcon ?? "figure.mixed.cardio"` |
| `sortedPoints` | `[SessionPoint]` | Sorted by `timestamp` |

---

### `SessionPoint`

One GPS sample inside a session.

| Property | Type |
|---|---|
| `timestamp` | `Date` |
| `latitude` | `Double` |
| `longitude` | `Double` |
| `altitude` | `Double` |
| `speed` | `Double` |
| `horizontalAccuracy` | `Double` |
| `session` | `Session?` |

**Computed:** `coordinate: CLLocationCoordinate2D`

---

### `SurgeSession`

A workout day — the top-level envelope that groups all exercises done in one session.

| Property | Type | Notes |
|---|---|---|
| `name` | `String` | Auto-named on creation, e.g. `"Morning · Jun 20"` |
| `date` | `Date` | Start-of-day anchor (used for calendar grouping) |
| `createdAt` | `Date` | Exact creation time (used for sorting and expiry) |
| `endedAt` | `Date?` | nil while "current"; set when user manually ends the workout |
| `plan` | `Plan?` | Template this workout was instantiated from |
| `route` | `Route?` | Set on the first GPS run in the session |
| `sessions` | `[Session]` | Nullify delete rule, inverse `Session.surgeSession` |

**Lifecycle constants:**

| Constant | Value | Meaning |
|---|---|---|
| `currentSurgeExpiryInterval` | `3600 s` | A surge session expires 1 hour after its last activity |

**Computed / static helpers:**

| Member | Notes |
|---|---|
| `lastActivityAt` | `max(createdAt, last session startedAt)` |
| `isCurrent` | True while `endedAt == nil` and inside the 1-hour window |
| `totalDurationSeconds` | Sum of all child session durations |
| `totalDistanceMeters` | Sum of all child session distances |
| `autoName(for:)` | Returns `"Morning · Jun 20"` style string based on time of day |
| `current(in:)` | Fetches the most recent unexpired surge session, or nil |
| `currentOrNew(in:)` | Gets current or inserts a brand-new auto-named one |

---

### `PlanGroup`

A named container for plans. Groups can be empty.

| Property | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `createdAt` | `Date` | |
| `cardGradientIndex` | `Int` | Index into `planGradients` array |
| `isFavorite` | `Bool` | |
| `plans` | `[Plan]` | Nullify delete rule — deleting a group orphans plans, not deletes them |

**Computed:** `sortedPlans` — sorted by `createdAt` descending

---

### `Plan`

A reusable workout template. Route-agnostic — just a list of exercise targets.

| Property | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `createdAt` | `Date` | |
| `items` | `[PlanItem]` | Cascade delete, inverse `PlanItem.plan` |
| `surgeSessions` | `[SurgeSession]` | Inverse of `SurgeSession.plan` — all times this plan has been executed |
| `group` | `PlanGroup?` | Optional group membership |
| `isFavorite` | `Bool` | |
| `cardGradientIndex` | `Int` | Index into `planGradients` array |

**Computed:** `sortedItems` — sorted by `order`

---

### `PlanItem`

One step in a plan — an exercise with a target.

| Property | Type | Notes |
|---|---|---|
| `order` | `Int` | Position in the plan sequence |
| `workoutType` | `WorkoutItemType` | |
| `measure` | `WorkoutMeasure` | |
| `targetValue` | `Double` | e.g. `400` for 400m run, `10` for 10 reps |
| `targetSeconds` | `Double?` | Optional performance target. For runs: pace in sec/km. For all others: total duration in seconds. |
| `plan` | `Plan?` | |

**Computed:** `displayTarget` — `measure.formatted(targetValue)`

---

### `CustomExercise`

A user-defined exercise type with its own name, icon, and allowed measures.

| Property | Type | Notes |
|---|---|---|
| `name` | `String` | Max 20 characters |
| `iconName` | `String` | SF Symbol name |
| `measures` | `[WorkoutMeasure]` | At least one required. When multiple, the recording gate shows a segmented measure picker. |
| `sortOrder` | `Int` | |
| `createdAt` | `Date` | |

---

## Enums

### `WorkoutItemType`

Built-in exercise types. All cases are `Codable`, `CaseIterable`, `Identifiable`.

| Case | Display Name | Allowed Measures |
|---|---|---|
| `.run` | Run | meters, laps |
| `.lunge` | Lunge | meters, yards, reps |
| `.burpeeBroadJump` | Burpee Broad Jump | meters, yards, reps |
| `.row` | Row | meters |
| `.wallBall` | Wall Balls | reps |
| `.rest` | Break | minutes |

Each case also provides `shortName` (used in compact chips) and `systemImage` (SF Symbol).

---

### `WorkoutMeasure`

| Case | Display | Example formatted output |
|---|---|---|
| `.meters` | Meters | `"400m"`, `"1.0km"` |
| `.yards` | Yards | `"24yd"` |
| `.laps` | Laps | `"3 laps"` |
| `.reps` | Reps | `"10 reps"` |
| `.minutes` | Minutes | `"30 sec"`, `"2 mins"` |

---

### `SegmentDirection`

Stored as `RouteSegment.endLabel` (raw `String` value for SwiftData compatibility).

| Case | Raw Value | Alert Title | Alert Color |
|---|---|---|---|
| `.straight` | `"Straight"` | STRAIGHT | green |
| `.left` | `"Left"` | TURN LEFT | orange |
| `.right` | `"Right"` | TURN RIGHT | orange |
| `.around` | `"Turnaround"` | TURN AROUND | orange |
| `.end` | `"End"` | FINISH | green |

`.reversed` mirrors left↔right (straight and around are symmetric) — used when running a route from the end rather than the start.

---

## Relationship Summary

```
PlanGroup ──(nullify)──> Plan ──(cascade)──> PlanItem
                          │
                          └──(inverse)──> SurgeSession ──(nullify)──> Session ──(cascade)──> SessionPoint
                                               │
                                               └──> Route ──(cascade)──> RoutePoint
                                                         └──(cascade)──> RouteSegment
                                                         └──(cascade)──> Session (same sessions as above)
```

**Delete rules at a glance:**

| Relationship | Rule | Effect |
|---|---|---|
| `Plan.items` | cascade | Deleting a plan deletes all its `PlanItem`s |
| `PlanGroup.plans` | nullify | Deleting a group orphans its plans (they become ungrouped) |
| `Route.definitionPoints` | cascade | Deleting a route deletes all its GPS definition points |
| `Route.segments` | cascade | Deleting a route deletes all its segments |
| `Route.sessions` | cascade | Deleting a route deletes all sessions ever run on it |
| `Session.points` | cascade | Deleting a session deletes its GPS trace |
| `SurgeSession.sessions` | nullify | Deleting a surge session orphans its child sessions |
