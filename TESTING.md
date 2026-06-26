# surge15 — Testing Checklist

Each screen lists two categories:
- **Pure Logic** — unit tests using the Swift Testing framework. No UI, no GPS, no device required.
- **UI State** — UI tests using XCUIAutomation, or manual verification on the simulator.

---

## Routes Map Screen (`RoutesHomeView`)

### Pure Logic
- [ ] `clusterRoutes(_:withinMeters:)` — two routes within 100m collapse into one cluster
- [ ] `clusterRoutes(_:withinMeters:)` — two routes outside 100m produce two separate clusters
- [ ] `clusterRoutes(_:withinMeters:)` — transitive clustering: A→B and B→C within threshold collapses all three
- [ ] `clusterRoutes(_:withinMeters:)` — empty input returns empty output
- [ ] `suggestedRoutes` — returns up to 2 nearest routes when user location is known
- [ ] `suggestedRoutes` — deduplicates routes within 50m of each other (keeps the one with more sessions)
- [ ] `suggestedRoutes` — falls back to top 2 by session count when no user location
- [ ] `nearestRoute` — returns the single closest route to user coordinate
- [ ] `nearestRoute` — returns nil when no routes exist
- [ ] `Route.distanceMeters` — sums segment distances when segments exist
- [ ] `Route.distanceMeters` — falls back to raw GPS trace length when no segments
- [ ] `Route.startCoordinate` — returns first definition point
- [ ] `Route.endCoordinate` — returns last definition point

### UI State
- [ ] Empty state renders "No Routes Yet" when route list is empty
- [ ] Map mode shows a pin for each route
- [ ] List mode shows a row for each route with name, distance, and run count
- [ ] Map/list toggle switches the view
- [ ] Long-pressing a route row shows Edit, Favorite, Delete in context menu
- [ ] Delete confirmation alert appears and can be cancelled without deleting
- [ ] Favorite toggle updates the heart icon immediately
- [ ] `+` button opens `CreateRouteView`
- [ ] Location denied shows the black overlay and "Switch to List View" button

---

## Route Peek Sheet (`RoutePeekSheet`)

### Pure Logic
- [ ] `Formatters.distance` — formats meters below 1000 as "Xm"
- [ ] `Formatters.distance` — formats 1000m+ as "X.Xkm"

### UI State
- [ ] Sheet shows route name and formatted distance
- [ ] Go button is present and tappable
- [ ] Tapping Go triggers the route recording navigation
- [ ] Tapping outside the sheet (background scrim) dismisses it

---

## Create Route (`CreateRouteView`)

### Pure Logic
- [ ] `Route.totalDistance(coordinates:)` — returns 0 for a single point
- [ ] `Route.totalDistance(coordinates:)` — returns correct sum for a known set of coordinates
- [ ] Save is blocked when total distance is below 10m (minimum route check)

### UI State
- [ ] GPS warm-up overlay appears on launch and disappears after acquiring location
- [ ] Record pill is inactive before tapping; turns red and active after tapping
- [ ] Direction pad (Left / Around / Right) appears only while recording
- [ ] Distance pill updates as points are recorded
- [ ] Stop button shows "Route Too Short" alert if distance is under 10m
- [ ] Valid route shows save confirmation and returns to the routes screen

---

## Edit Route (`EditRouteView`)

### Pure Logic
- [ ] No meaningful pure logic — all formatting handled by `Route` model or `Formatters`

### UI State
- [ ] Name field is pre-filled with existing route name
- [ ] Saving with empty name is blocked or shows an error
- [ ] Saving updates the route name in the list
- [ ] Delete shows a confirmation alert
- [ ] Confirming delete removes the route and dismisses the sheet

---

## Plans Home (`PlansHomeView`)

### Pure Logic
- [ ] `allPlansSorted` — plans are ordered by `surgeSessions.count` descending
- [ ] `favoriteGroupCount` — returns count of groups with `isFavorite == true`
- [ ] `favoritePlanCount` — returns count of plans with `isFavorite == true`

### UI State
- [ ] Empty state renders when no groups and no plans exist
- [ ] Groups row appears when at least one group exists
- [ ] "For You" row always renders (Favorite Groups + Favorite Plans cards)
- [ ] All Plans section shows all plans regardless of group membership
- [ ] Long-pressing a plan shows: Edit Plan, Edit Color, Rename Plan, Add to Group, Delete Plan
- [ ] Long-pressing a group shows: Rename Group, Change Color, Delete Group
- [ ] Delete confirmation alert cancels without deleting
- [ ] `+` menu offers "New Group" and "New Plan"
- [ ] "New Group" opens `CreatePlanGroupView`
- [ ] "New Plan" opens `CreatePlanView`

---

## Plan Group Detail (`PlanGroupDetailView`)

### Pure Logic
- [ ] `sortedPlans` — sorted by `surgeSessions.count` descending

### UI State
- [ ] Empty state shows "No plans in this group yet" with "Add First Plan" CTA
- [ ] Plans in the group are listed as rows
- [ ] Long-pressing a plan shows: Edit Plan, Edit Color, Rename Plan, Move to Group, Delete Plan
- [ ] Heart button in toolbar toggles group favorite
- [ ] `+` button opens `CreatePlanView` pre-set to this group

---

## Create / Edit Plan (`CreatePlanView`)

### Pure Logic
- [ ] `isValid` — false when plan name is empty
- [ ] `isValid` — false when draft items list is empty
- [ ] `isValid` — true when name is non-empty and at least one item exists
- [ ] `defaultTarget(for:type:)` — returns 400 for meters on a run
- [ ] `defaultTarget(for:type:)` — returns 1 for laps
- [ ] `defaultTarget(for:type:)` — returns 10 for reps
- [ ] `defaultTarget(for:type:)` — returns 2 for minutes
- [ ] `currentPresets` — returns meter presets for `.meters` measure
- [ ] `currentPresets` — returns rep presets for `.reps` measure
- [ ] `chip(_:)` label — formats values below 1000 as "Xm", 1000+ as "X.Xk"
- [ ] `chip(_:)` label — formats minutes below 1 as "Xs" (seconds)
- [ ] `targetChipLabel(_:)` — formats pace correctly as "M:SS" for runs
- [ ] `targetChipLabel(_:)` — formats duration using `Formatters.duration` for non-runs

### UI State
- [ ] Type chip grid shows all 6 exercise types
- [ ] Selecting a type updates the measure picker options
- [ ] Break type hides the pace/time target row entirely
- [ ] Selecting a measure updates the preset chips
- [ ] Tapping a preset chip selects it (highlighted blue)
- [ ] "Add to Plan" appends item to the draft list
- [ ] Save button is disabled when name is empty or no items added
- [ ] Draft items can be swiped to delete
- [ ] Draft items can be reordered via drag
- [ ] Edit mode: form pre-fills with existing plan's name, group, and all exercises
- [ ] Edit mode: navigation title shows "Edit Plan" not "New Plan"
- [ ] Saving in edit mode replaces items (does not create a duplicate plan)

---

## Plan Detail (`PlanDetailView`)

### Pure Logic
- [ ] `canStart` — false when no route is selected
- [ ] `canStart` — false when plan has no items
- [ ] `canStart` — true when a route is selected and items exist
- [ ] `paceLabel(_:)` — formats 330 seconds as "5:30"
- [ ] `paceLabel(_:)` — formats 210 seconds as "3:30"

### UI State
- [ ] Route picker shows all available routes as scrollable chips
- [ ] Selecting a route highlights the chip and enables Start
- [ ] Start button is disabled with no route selected
- [ ] Exercise timeline shows all plan items in order
- [ ] Target pace / time target renders in blue for items that have one
- [ ] Heart toggle in toolbar toggles `plan.isFavorite`
- [ ] No routes available shows the warning message

---

## Surge Session Detail (`SurgeSessionDetailView`)

### Pure Logic
- [ ] `satisfiedMapping` — matches a run session to its plan item by `workoutType == .run`
- [ ] `satisfiedMapping` — does not double-claim sessions (each session satisfies at most one item)
- [ ] `satisfiedMapping` — handles the case where there are more sessions than plan items
- [ ] `resultText` — includes duration, distance, and pace for completed run sessions
- [ ] `resultText` — returns "—" when session has no duration or distance
- [ ] `paceVsTargetLine` — shows "Beat X target" when actual pace ≤ target pace
- [ ] `paceVsTargetLine` — shows "Missed X target" when actual pace > target pace
- [ ] `paceVsTargetLine` — shows "No Pace Target" when run item has no `targetSeconds`
- [ ] `paceVsTargetLine` — shows "Target X · pace unavailable" when target set but distance is 0
- [ ] `paceVsTargetLine` — shows "No Time Target" when non-run item has no `targetSeconds`
- [ ] `elapsedActiveTime` — subtracts paused intervals from total elapsed
- [ ] `paceLabel(_:)` — formats seconds-per-km as "M:SS"

### UI State
- [ ] Elapsed timer ticks while session is active
- [ ] Nav title turns orange while paused
- [ ] Pause/Go button toggles correctly
- [ ] Skip marks current item as skipped in the timeline
- [ ] Back restores the last skipped item
- [ ] Start button is disabled when no actionable items remain
- [ ] Completed items show green result text + pace vs target line
- [ ] Pending items show target in blue
- [ ] Skipped items render in italic with "Skipped" label
- [ ] Auto mode toggle shows confirmation alert before switching
- [ ] Stop shows confirmation before ending the session
- [ ] Reorder sheet opens when future items exist
- [ ] Workout Complete overlay fires after last item in auto mode

---

## Session Recording / GPS Run (`SessionRecordingView`)

### Pure Logic
- [ ] `checkSegmentBoundaries()` — fires when `currentLapDistance` crosses a segment end distance
- [ ] `checkSegmentBoundaries()` — in reverse mode, thresholds are `totalDist - forwardEnd`
- [ ] `SegmentDirection.reversed` — left returns right, right returns left
- [ ] `SegmentDirection.reversed` — straight and around return themselves
- [ ] `gateCoordinate` — returns `endCoordinate` when `startFromEnd == true`
- [ ] `gateCoordinate` — returns `startCoordinate` when `startFromEnd == false`
- [ ] `paceValueColor` — returns green when current pace beats target
- [ ] `paceValueColor` — returns red when current pace misses target
- [ ] `paceValueColor` — returns primary when no target set

### UI State
- [ ] Gate overlay shows distance to start (or end) with status color (red/orange/green)
- [ ] Start button is disabled until within 20m of gate coordinate
- [ ] "From Beginning / From End" picker switches the gate target
- [ ] Countdown overlay fires on Start and counts down
- [ ] Active screen shows timer, distance, pace metrics
- [ ] Turn alert overlay fires with correct direction at each segment boundary
- [ ] Lap pill appears on each lap completion
- [ ] Pace card shows target label when a pace target is set
- [ ] Pace value turns green/red based on current vs target pace

---

## Exercise Recording (`ExerciseRecordingView`)

### Pure Logic
- [ ] `currentPresets` — returns meter presets for `.meters` measure
- [ ] `currentPresets` — returns rep presets for `.reps` measure
- [ ] `currentPresets` — returns minute presets for `.minutes` measure
- [ ] `elapsed` — increments correctly from `startedAt`

### UI State
- [ ] Gate screen shows measure picker only when type has multiple measures
- [ ] Gate is skipped (auto-starts countdown) when launched from a plan item
- [ ] Countdown ticks from configured value down to 0
- [ ] Active screen shows running timer
- [ ] Completing the exercise navigates back to the timeline (no summary screen when in a surge session)
- [ ] Summary screen appears when exercised is done outside a surge session

---

## Calendar / Sessions (`CalendarHomeView`)

### Pure Logic
- [ ] `activeDates` — returns correct set of start-of-day dates for all surge sessions
- [ ] `sessionsOnSelectedDate` — returns only sessions whose `date` matches selected day
- [ ] `quoteForSelectedDate` — returns a today nudge quote when selected date is today
- [ ] `quoteForSelectedDate` — returns a future quote when selected date is in the future
- [ ] `quoteForSelectedDate` — returns a rest day quote for a past day with no sessions
- [ ] Quote is deterministic for a given day (seeded by day index, not random each render)

### UI State
- [ ] Calendar grid shows green dots on days with sessions
- [ ] Tapping a day with sessions shows the surge session rows
- [ ] Tapping a day with no sessions shows the quote
- [ ] Tapping a surge session row navigates to `SurgeSessionDetailView`
- [ ] Month navigation arrows move forward and backward correctly
- [ ] Calendar / Analytics segmented picker switches to `AnalyticsView`

---

## Analytics (`AnalyticsView`)

### Pure Logic
- [ ] `filteredSessions` — 7D range excludes sessions older than 7 days
- [ ] `filteredSessions` — All range includes every session
- [ ] `avgPaceSeconds` — correctly averages pace across filtered run sessions
- [ ] `bestPaceSeconds` — returns the minimum (fastest) pace
- [ ] `workoutDays` — groups sessions by calendar day correctly

### UI State
- [ ] Frequency chart renders bars for days with sessions
- [ ] Pace chart renders points for run sessions only
- [ ] Headline stat updates when dragging/tapping a chart point
- [ ] Switching date range clears any active selection
- [ ] Empty state renders gracefully when no sessions in selected range

---

## Settings (`SettingsHomeView`)

### Pure Logic
- [ ] No meaningful pure logic — all state backed by `@AppStorage`

### UI State
- [ ] Countdown duration stepper increments and decrements by 1
- [ ] Rest duration stepper increments and decrements by 1
- [ ] Values persist after dismissing and reopening Settings
- [ ] "Exercise Library" row navigates to `ExerciseLibraryView`

---

## Exercise Library (`ExerciseLibraryView`)

### Pure Logic
- [ ] `hiddenBuiltins` — correctly parses a comma-separated string into a Set
- [ ] `addToHidden` — adds the name and persists it to `@AppStorage`
- [ ] `removeFromHidden` — removes the name and persists the updated set
- [ ] `trimmedName` — strips leading/trailing whitespace from the exercise name
- [ ] Custom exercise name is capped at 20 characters
- [ ] Save is blocked when no measures are selected (at least one required)

### UI State
- [ ] Built-in exercises render with toggle switches
- [ ] Toggling a built-in hides/shows it in the exercise picker
- [ ] "Add Custom Exercise" opens `ExerciseEditSheet`
- [ ] Name field enforces 20-character limit visually
- [ ] Selecting multiple measures enables the segmented picker in `ExerciseRecordingView`
- [ ] Deleting a custom exercise removes it from the list with confirmation
