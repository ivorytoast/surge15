//
//  SurgeSessionDetailView.swift
//  surge15
//
//  Live:  unified timeline + bottom action bar (Back / Skip / Stop / Pause / Go).
//  Past:  read-only timeline + summary stats card.
//

import SwiftUI
import SwiftData
import MapKit

// MARK: - Pending exercise (queued, not yet started)

private struct PendingExercise: Identifiable {
    let id = UUID()
    let type: WorkoutItemType?   // nil for custom exercises
    let customName: String?
    let customIcon: String?
    let measure: WorkoutMeasure
    let availableMeasures: [WorkoutMeasure]
    let targetValue: Double

    init(type: WorkoutItemType, measure: WorkoutMeasure, targetValue: Double) {
        self.type = type
        self.customName = nil
        self.customIcon = nil
        self.measure = measure
        self.availableMeasures = [measure]
        self.targetValue = targetValue
    }

    init(customName: String, customIcon: String, measures: [WorkoutMeasure], targetValue: Double = 10) {
        self.type = nil
        self.customName = customName
        self.customIcon = customIcon
        self.measure = measures.first ?? .reps
        self.availableMeasures = measures
        self.targetValue = targetValue
    }

    var displayName: String { type?.displayName ?? customName ?? "Exercise" }
    var systemImage: String { type?.systemImage ?? customIcon ?? "figure.mixed.cardio" }

    var displayTarget: String {
        type == .run ? "Route run" : measure.formatted(targetValue)
    }
}

// MARK: - Custom exercise recording request

private struct CustomRecordingRequest: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let measures: [WorkoutMeasure]
    let targetValue: Double
}

// MARK: - Direct GPS run (plan item bypass — skips RouteRunSetupView)

private struct DirectRunDestination: Identifiable, Hashable {
    let id = UUID()
    let route: Route
    let mode: SessionMode
    let target: Double
    let targetPaceSecondsPerKm: Double?

    static func == (lhs: DirectRunDestination, rhs: DirectRunDestination) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - Reorder entry (unified plan item + pending exercise)

fileprivate enum ReorderEntry: Identifiable {
    case planItem(PlanItem)
    case pending(PendingExercise)

    var id: String {
        switch self {
        case .planItem(let item): return "plan-\(item.id)"
        case .pending(let p): return "pending-\(p.id)"
        }
    }
    var displayName: String {
        switch self { case .planItem(let i): return i.workoutType.displayName; case .pending(let p): return p.displayName }
    }
    var systemImage: String {
        switch self { case .planItem(let i): return i.workoutType.systemImage; case .pending(let p): return p.systemImage }
    }
    var subtitle: String {
        switch self { case .planItem(let i): return i.displayTarget; case .pending(let p): return p.displayTarget }
    }
}

// MARK: - Timeline entry

private enum SurgeTimelineEntry: Identifiable {
    case planItem(PlanItem, index: Int)
    case adHocSession(Session)
    case pending(PendingExercise)

    var id: String {
        switch self {
        case .planItem(let item, _): return "item-\(item.id)"
        case .adHocSession(let s): return "session-\(s.id)"
        case .pending(let p): return "pending-\(p.id)"
        }
    }
}

// MARK: - Main view

struct SurgeSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var surgeSession: SurgeSession

    @State private var showingEndConfirm = false
    @State private var showingAddExercise = false
    /// Exercises queued to be done — configured and added via + but not yet started.
    @State private var pendingAdHocItems: [PendingExercise] = []
    /// Holds the type while waiting for the add sheet to fully dismiss before showing config.
    @State private var pendingConfigType: WorkoutItemType? = nil
    @State private var configuringExercise: WorkoutItemType? = nil
    @State private var recordingExercise: WorkoutItemType?
    @State private var recordingMeasure: WorkoutMeasure? = nil
    @State private var recordingTarget: Double? = nil
    @State private var routeForSetup: Route?
    @State private var routeRunMeasure: WorkoutMeasure? = nil
    @State private var routeRunTarget: Double? = nil
    @State private var recordingCustomRequest: CustomRecordingRequest? = nil
    @State private var directRunDestination: DirectRunDestination? = nil
    @State private var showingAutoModeConfirm = false
    @State private var showWorkoutComplete = false
    @AppStorage(hiddenBuiltinExercisesKey) private var hiddenBuiltinsRaw: String = ""
    /// Local-only skip stack — order tracked so Back can undo the last skip.
    @State private var skippedItems: [PersistentIdentifier] = []
    @State private var skippedPendingIDs: [UUID] = []
    @State private var isPaused = false
    @State private var pauseStartedAt: Date? = nil
    @State private var totalPausedSeconds: TimeInterval = 0
    @State private var flashingGreen = false
    @State private var now = Date()
    /// Current timeline order for plan items. Empty = use plan's natural sort order.
    @State private var timelineOrder: [PersistentIdentifier] = []
    @State private var showingReorder = false
    @State private var autoModeEnabled: Bool = false
    @AppStorage(autoRestDurationKey) private var autoRestDuration: Int = autoRestDurationDefault
    @State private var autoRestRemaining: TimeInterval? = nil
    @State private var autoRestTask: Task<Void, Never>? = nil
    /// Session count captured when an exercise starts — used to detect completion on sheet dismiss.
    @State private var sessionCountSnapshot: Int = 0

    private var isLive: Bool { surgeSession.isCurrent }

    var body: some View {
        coreView
            .sheet(item: $recordingExercise, onDismiss: {
                let snapshot = sessionCountSnapshot
                recordingMeasure = nil
                recordingTarget = nil
                if autoModeEnabled && surgeSession.sessions.count > snapshot {
                    handleAutoModeExerciseComplete()
                }
            }) { type in
                ExerciseRecordingView(workoutType: type, measure: recordingMeasure,
                                      targetValue: recordingTarget, surgeSession: surgeSession)
            }
            .sheet(item: $recordingCustomRequest, onDismiss: {
                let snapshot = sessionCountSnapshot
                if autoModeEnabled && surgeSession.sessions.count > snapshot {
                    handleAutoModeExerciseComplete()
                }
            }) { req in
                ExerciseRecordingView(customName: req.name, customIcon: req.icon,
                                      measures: req.measures, targetValue: req.targetValue,
                                      surgeSession: surgeSession)
            }
            .sheet(isPresented: $showingReorder) { reorderSheet }
            .navigationDestination(item: $routeForSetup) { route in
                RouteRunSetupView(route: route, presetMeasure: routeRunMeasure, presetTarget: routeRunTarget)
            }
            .navigationDestination(item: $directRunDestination) { dest in
                SessionRecordingView(route: dest.route, initialMode: dest.mode, initialTarget: dest.target,
                                     targetPaceSecondsPerKm: dest.targetPaceSecondsPerKm)
            }
            .alert("End this workout?", isPresented: $showingEndConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("End", role: .destructive) { surgeSession.endedAt = Date(); dismiss() }
            } message: {
                Text("You can still view this workout in the calendar.")
            }
            .alert("Enable Auto Mode?", isPresented: $showingAutoModeConfirm) {
                Button("Let's Go!") {
                    autoModeEnabled = true
                    if currentItemIndex != nil || firstActivePending != nil { autoStartNextItem() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Auto Mode will immediately start your first exercise and automatically begin each following one after a \(autoRestDuration)s rest. Tap the timer to skip rest early.")
            }
            .onChange(of: autoModeEnabled) { _, enabled in if !enabled { cancelAutoRest() } }
            .onChange(of: routeForSetup == nil) { wasNil, isNil in
                if !wasNil && isNil && autoModeEnabled && surgeSession.sessions.count > sessionCountSnapshot {
                    handleAutoModeExerciseComplete()
                }
            }
            .onChange(of: directRunDestination == nil) { wasNil, isNil in
                if !wasNil && isNil && autoModeEnabled && surgeSession.sessions.count > sessionCountSnapshot {
                    handleAutoModeExerciseComplete()
                }
            }
            .onDisappear { autoRestTask?.cancel() }
    }

    private var coreView: some View {
        ScrollView {
            VStack(spacing: 20) {
                workoutTimeline
                    .padding(.horizontal)
                    .padding(.top, isLive ? 8 : 0)
                if !isLive, let total = surgeSession.totalDurationSeconds {
                    summaryCard(total: total).padding(.horizontal)
                }
            }
            .padding(.bottom, isLive ? 100 : 24)
        }
        .overlay {
            if showWorkoutComplete {
                WorkoutCompleteOverlay { withAnimation { showWorkoutComplete = false } }
                    .transition(.opacity)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(surgeSession.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(navBarTintColor, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { principalTitle }
            if isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddExercise = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { if isLive { actionBar } }
        .onAppear {
            if timelineOrder.isEmpty, let plan = surgeSession.plan {
                timelineOrder = plan.sortedItems.map(\.id)
            }
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(isPresented: $showingAddExercise, onDismiss: {
            if let type = pendingConfigType { configuringExercise = type; pendingConfigType = nil }
        }) {
            AddExerciseSheet(
                routeName: surgeSession.route?.name,
                hiddenBuiltinRawValues: hiddenBuiltinsRaw,
                onRouteRun: {
                    pendingAdHocItems.append(PendingExercise(type: .run, measure: .laps, targetValue: 1))
                    showingAddExercise = false
                },
                onSelectBuiltin: { type in pendingConfigType = type; showingAddExercise = false },
                onSelectCustom: { exercise in
                    pendingAdHocItems.append(PendingExercise(customName: exercise.name,
                                                             customIcon: exercise.iconName,
                                                             measures: exercise.measures))
                    showingAddExercise = false
                }
            )
        }
        .sheet(item: $configuringExercise) { type in
            ExerciseConfigSheet(type: type) { measure, value in
                pendingAdHocItems.append(PendingExercise(type: type, measure: measure, targetValue: value))
            }
        }
    }

    // MARK: - Elapsed time & title color

    private var elapsedActiveTime: TimeInterval {
        let currentPause: TimeInterval = isPaused ? now.timeIntervalSince(pauseStartedAt ?? now) : 0
        return max(0, now.timeIntervalSince(surgeSession.createdAt) - totalPausedSeconds - currentPause)
    }

    private var titleColor: Color {
        if flashingGreen { return .green }
        if isPaused { return .orange }
        return .primary
    }

    private var navBarTintColor: Color {
        if flashingGreen { return Color.green.opacity(0.15) }
        if isPaused { return Color.orange.opacity(0.12) }
        return Color.clear
    }

    @ViewBuilder
    private var principalTitle: some View {
        if isLive {
            Text(Formatters.duration(elapsedActiveTime))
                .font(.headline.monospacedDigit())
                .foregroundStyle(titleColor)
                .animation(.easeInOut(duration: 0.25), value: flashingGreen)
                .animation(.easeInOut(duration: 0.2), value: isPaused)
        } else {
            Text(surgeSession.name).font(.headline)
        }
    }

    // MARK: - Timeline ordering

    private var orderedPlanItems: [PlanItem] {
        guard let plan = surgeSession.plan else { return [] }
        guard !timelineOrder.isEmpty else { return plan.sortedItems }
        return timelineOrder.compactMap { id in plan.items.first { $0.id == id } }
    }

    /// Number of items that cannot be reordered: all items up to and including the current one.
    private var frozenCount: Int {
        guard let idx = currentItemIndex else { return orderedPlanItems.count }
        return idx + 1
    }

    /// All reorderable future items — remaining plan items interleaved with pending exercises.
    private var mutableFutureEntries: [ReorderEntry] {
        let futurePlan = orderedPlanItems.dropFirst(frozenCount).map { ReorderEntry.planItem($0) }
        let futurePending = pendingAdHocItems.map { ReorderEntry.pending($0) }
        return futurePlan + futurePending
    }

    /// Apply a reordered list back into `timelineOrder` and `pendingAdHocItems`.
    private func applyReorder(_ newOrder: [ReorderEntry]) {
        let frozenIDs = orderedPlanItems.prefix(frozenCount).map(\.id)
        let newPlanIDs = newOrder.compactMap { entry -> PersistentIdentifier? in
            guard case .planItem(let item) = entry else { return nil }
            return item.id
        }
        timelineOrder = Array(frozenIDs) + newPlanIDs
        pendingAdHocItems = newOrder.compactMap { entry -> PendingExercise? in
            guard case .pending(let p) = entry else { return nil }
            return p
        }
    }

    private var adHocSessions: [Session] {
        let claimed = claimedSessionIDs
        return surgeSession.sortedSessions.filter { !claimed.contains($0.id) }
    }

    private var timelineEntries: [SurgeTimelineEntry] {
        let pendingEntries = pendingAdHocItems.map { SurgeTimelineEntry.pending($0) }
        guard surgeSession.plan != nil else {
            return surgeSession.sortedSessions.map { .adHocSession($0) } + pendingEntries
        }
        let items = orderedPlanItems
        var entries: [SurgeTimelineEntry] = items.enumerated().map { .planItem($1, index: $0) }
        // Pending items appear right after plan items (future work), completed ad-hoc sessions at the end
        entries += pendingEntries
        entries += adHocSessions.map { .adHocSession($0) }
        return entries
    }

    // MARK: - Timeline view

    @ViewBuilder
    private var workoutTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(surgeSession.plan != nil ? "Workout Plan" : "Exercises")
                    .font(.title3.bold())
                Spacer()
                if let plan = surgeSession.plan, !plan.items.isEmpty {
                    Text("\(satisfiedItemIDs.count) / \(plan.items.count) done")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Reorder button: any future plan items OR pending items can be moved
                    if isLive && !mutableFutureEntries.isEmpty {
                        Button { showingReorder = true } label: {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 8)
                    }
                }
            }

            let entries = timelineEntries
            if entries.isEmpty {
                emptyTimelineState
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                        timelineEntryView(entry, entryIndex: idx, total: entries.count)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func timelineEntryView(_ entry: SurgeTimelineEntry, entryIndex: Int, total: Int) -> some View {
        let isLast = entryIndex == total - 1
        switch entry {
        case .planItem(let item, let index):
            timelineRow(item: item, index: index, isLast: isLast)
        case .adHocSession(let session):
            adHocTimelineRow(session: session, isLast: isLast)
        case .pending(let exercise):
            let isSkipped = skippedPendingIDSet.contains(exercise.id)
            let isPendingCurrent = isLive && !isSkipped && currentItemIndex == nil && firstActivePending?.id == exercise.id
            pendingTimelineRow(exercise: exercise, isLast: isLast, isCurrent: isPendingCurrent, isSkipped: isSkipped)
        }
    }

    private var reorderSheet: some View {
        let frozenEntries: [ReorderEntry] = orderedPlanItems.prefix(frozenCount).map { ReorderEntry.planItem($0) }
        return ReorderSheet(
            frozenEntries: frozenEntries,
            mutableEntries: mutableFutureEntries,
            onDone: applyReorder
        )
    }

    private var emptyTimelineState: some View {
        HStack(spacing: 12) {
            Image(systemName: "plus.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(isLive ? "Tap + to add your first exercise." : "No exercises recorded.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func timelineRow(item: PlanItem, index: Int, isLast: Bool) -> some View {
        let done = satisfiedItemIDs.contains(item.id)
        let skipped = skippedItemIDs.contains(item.id)
        let isCurrent = isLive && currentItemIndex == index
        let matched = claimedSession(for: item)

        return HStack(alignment: .top, spacing: 14) {
            // Left: circle + connecting line
            VStack(spacing: 0) {
                timelineCircle(done: done, skipped: skipped, isCurrent: isCurrent)
                    .frame(width: 32, height: 32)
                if !isLast {
                    Rectangle()
                        .fill(done ? Color.green.opacity(0.35) : Color(.separator).opacity(0.6))
                        .frame(width: 2)
                        .padding(.vertical, 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            // Right: content
            VStack(alignment: .leading, spacing: 5) {
                Text(item.workoutType.displayName)
                    .font(isCurrent ? .headline.bold() : .headline)
                    .foregroundStyle(done || skipped ? .secondary : .primary)
                    .strikethrough(done)
                    .italic(skipped)

                if done, let s = matched {
                    Text(resultText(s))
                        .font(.caption)
                        .foregroundStyle(.green)
                    paceVsTargetLine(item: item, session: s)
                } else if skipped {
                    Text("Skipped")
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                } else {
                    Text(item.displayTarget)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.primary.opacity(0.6) : Color.secondary)
                    if let ts = item.targetSeconds {
                        Text(item.workoutType == .run
                             ? "Target: \(paceLabel(ts))/km"
                             : "Target: \(Formatters.duration(ts))")
                            .font(.caption2)
                            .foregroundStyle(.blue.opacity(0.8))
                    }
                }

            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private func adHocTimelineRow(session: Session, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                adHocCircle()
                    .frame(width: 32, height: 32)
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.4))
                        .frame(width: 2)
                        .padding(.vertical, 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(session.exerciseDisplayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(resultText(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private func adHocCircle() -> some View {
        ZStack {
            Circle().fill(Color.green.opacity(0.15))
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
        }
    }

    private func pendingTimelineRow(exercise: PendingExercise, isLast: Bool, isCurrent: Bool, isSkipped: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                timelineCircle(done: false, skipped: isSkipped, isCurrent: isCurrent)
                    .frame(width: 32, height: 32)
                if !isLast {
                    Rectangle()
                        .fill(Color(.separator).opacity(0.6))
                        .frame(width: 2)
                        .padding(.vertical, 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            VStack(alignment: .leading, spacing: 5) {
                Text(exercise.displayName)
                    .font(isCurrent ? .headline.bold() : .headline)
                    .foregroundStyle(isSkipped ? .secondary : .primary)
                    .italic(isSkipped)
                if isSkipped {
                    Text("Skipped")
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                } else {
                    Text(exercise.displayTarget)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.primary.opacity(0.6) : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    private func startPendingItem(_ exercise: PendingExercise) {
        cancelAutoRest()
        sessionCountSnapshot = surgeSession.sessions.count
        pendingAdHocItems.removeAll { $0.id == exercise.id }
        if exercise.type == .run, let route = surgeSession.route {
            routeRunMeasure = nil  // ad-hoc runs always show the config
            routeRunTarget = nil
            routeForSetup = route
        } else if let type = exercise.type {
            recordingMeasure = exercise.measure
            recordingTarget = exercise.targetValue
            recordingExercise = type
        } else {
            recordingCustomRequest = CustomRecordingRequest(
                name: exercise.customName ?? "",
                icon: exercise.customIcon ?? "figure.mixed.cardio",
                measures: exercise.availableMeasures,
                targetValue: exercise.targetValue
            )
        }
    }

    private func timelineCircle(done: Bool, skipped: Bool, isCurrent: Bool) -> some View {
        ZStack {
            if done {
                Circle().fill(Color.green.opacity(0.15))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.green)
            } else if skipped {
                Circle().fill(Color(.systemFill))
                Image(systemName: "forward.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            } else if isCurrent {
                Circle().fill(Color.blue)
                Circle().fill(.white).frame(width: 8, height: 8)
            } else {
                Circle().strokeBorder(Color(.separator), lineWidth: 2)
            }
        }
    }

    // MARK: - Summary card (past only)

    private func summaryCard(total: TimeInterval) -> some View {
        let count = surgeSession.sessions.count
        return HStack(spacing: 0) {
            statCell(value: Formatters.duration(total), label: "total time")
            if surgeSession.totalDistanceMeters > 0 {
                Divider().frame(height: 40)
                statCell(value: Formatters.distance(surgeSession.totalDistanceMeters), label: "distance")
            }
            Divider().frame(height: 40)
            statCell(value: "\(count)", label: count == 1 ? "exercise" : "exercises")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom action bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            // Mode toggle
            HStack(spacing: 2) {
                Button {
                    if autoModeEnabled {
                        autoModeEnabled = false
                        cancelAutoRest()
                    }
                } label: {
                    Text("Manual")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(!autoModeEnabled ? Color(.systemBackground) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(!autoModeEnabled ? .primary : Color(.tertiaryLabel))
                }
                .buttonStyle(.plain)

                Button {
                    if !autoModeEnabled { showingAutoModeConfirm = true }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.caption.weight(.bold))
                            .opacity(autoModeEnabled ? 1 : 0.4)
                        Text("Auto")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(autoModeEnabled ? Color.orange : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(autoModeEnabled ? .white : Color(.tertiaryLabel))
                    .animation(.easeInOut(duration: 0.2), value: autoModeEnabled)
                }
                .buttonStyle(.plain)
            }
            .padding(3)
            .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)

            HStack(spacing: 0) {
                // Back — undo last skip
                actionButton(icon: "arrow.uturn.backward.circle", label: "Back", color: .secondary) {
                    goBack()
                }
                .disabled(skippedItems.isEmpty && skippedPendingIDs.isEmpty)

                // Skip — advance past current item (or the next item during auto rest)
                actionButton(icon: "forward.fill", label: "Skip", color: .secondary) {
                    skipCurrentItem()
                }
                .disabled(currentItemIndex == nil && firstActivePending == nil)

                // Center — Start button or auto rest countdown ring
                if autoModeEnabled, let remaining = autoRestRemaining {
                    Button { skipAutoRest() } label: {
                        VStack(spacing: 3) {
                            ZStack {
                                Circle()
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 4)
                                    .frame(width: 50, height: 50)
                                Circle()
                                    .trim(from: 0, to: max(0, CGFloat(remaining) / CGFloat(max(1, autoRestDuration))))
                                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 50, height: 50)
                                    .rotationEffect(.degrees(-90))
                                    .animation(.linear(duration: 1), value: remaining)
                                Text("\(max(0, Int(ceil(remaining))))")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(.orange)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                            }
                            Text("Start Now")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                } else {
                    Button {
                        if let idx = currentItemIndex {
                            startItem(orderedPlanItems[idx])
                        } else if let first = firstActivePending {
                            startPendingItem(first)
                        }
                    } label: {
                        VStack(spacing: 3) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.green)
                            Text("Start")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .disabled(currentItemIndex == nil && firstActivePending == nil)
                }

                // Pause / Go toggle
                actionButton(
                    icon: isPaused ? "play.circle.fill" : "pause.circle.fill",
                    label: isPaused ? "Go" : "Pause",
                    color: isPaused ? .green : .orange
                ) {
                    isPaused ? resumeWorkout() : pauseWorkout()
                }
                .animation(.easeInOut(duration: 0.15), value: isPaused)

                // Stop — end the workout
                actionButton(icon: "stop.circle.fill", label: "Stop", color: .red) {
                    showingEndConfirm = true
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .padding(.bottom, 6)
        }
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private func actionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Session row (used by no-plan path via timelineEntries)

    private func sessionRow(_ session: Session, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.blue.opacity(0.10)).frame(width: 36, height: 36)
                    Image(systemName: session.exerciseSystemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.exerciseDisplayName).font(.headline)
                    Text(resultText(session)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Current item & action logic

    private var skippedItemIDs: Set<PersistentIdentifier> { Set(skippedItems) }

    private var currentItemIndex: Int? {
        guard surgeSession.plan != nil else { return nil }
        let items = orderedPlanItems
        return items.indices.first {
            !satisfiedItemIDs.contains(items[$0].id) && !skippedItemIDs.contains(items[$0].id)
        }
    }

    private var skippedPendingIDSet: Set<UUID> { Set(skippedPendingIDs) }

    private var firstActivePending: PendingExercise? {
        pendingAdHocItems.first(where: { !skippedPendingIDSet.contains($0.id) })
    }

    private func skipCurrentItem() {
        if let idx = currentItemIndex {
            skippedItems.append(orderedPlanItems[idx].id)
        } else if let first = firstActivePending {
            skippedPendingIDs.append(first.id)
        }
    }

    private func goBack() {
        if !skippedPendingIDs.isEmpty {
            skippedPendingIDs.removeLast()
        } else if !skippedItems.isEmpty {
            skippedItems.removeLast()
        }
    }

    private func pauseWorkout() {
        guard !isPaused else { return }
        isPaused = true
        pauseStartedAt = now
        // Freeze the auto rest countdown — keeps autoRestRemaining as-is so resume can continue from it
        autoRestTask?.cancel()
        autoRestTask = nil
    }

    private func resumeWorkout() {
        guard isPaused else { return }
        if let start = pauseStartedAt {
            totalPausedSeconds += now.timeIntervalSince(start)
        }
        isPaused = false
        pauseStartedAt = nil
        flashingGreen = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            flashingGreen = false
        }
        // Resume countdown from where it was paused
        if autoModeEnabled, let remaining = autoRestRemaining, remaining > 0 {
            startAutoRest(from: remaining)
        }
    }

    private func startItem(_ item: PlanItem) {
        cancelAutoRest()
        sessionCountSnapshot = surgeSession.sessions.count
        if item.workoutType == .run, let route = surgeSession.route {
            let mode: SessionMode = (item.measure == .meters || item.measure == .yards) ? .distance : .laps
            directRunDestination = DirectRunDestination(
                route: route, mode: mode, target: item.targetValue,
                targetPaceSecondsPerKm: item.targetSeconds
            )
        } else {
            recordingMeasure = item.measure
            recordingTarget = item.targetValue
            recordingExercise = item.workoutType
        }
    }

    // MARK: - Satisfaction logic

    private var satisfiedMapping: [PersistentIdentifier: Session] {
        guard let plan = surgeSession.plan else { return [:] }
        var result: [PersistentIdentifier: Session] = [:]
        var claimed = Set<PersistentIdentifier>()
        for item in plan.sortedItems {
            if let match = surgeSession.sortedSessions.first(where: { session in
                guard !claimed.contains(session.id) else { return false }
                guard session.workoutType == item.workoutType else { return false }
                switch item.measure {
                case .meters, .yards:
                    return session.distanceMeters >= item.targetValue || session.targetValue >= item.targetValue
                case .laps:
                    return Double(session.targetLaps) >= item.targetValue
                case .reps, .minutes:
                    return session.targetValue >= item.targetValue
                }
            }) {
                result[item.id] = match
                claimed.insert(match.id)
            }
        }
        return result
    }

    private var satisfiedItemIDs: Set<PersistentIdentifier> { Set(satisfiedMapping.keys) }
    private var claimedSessionIDs: Set<PersistentIdentifier> { Set(satisfiedMapping.values.map(\.id)) }
    private func claimedSession(for item: PlanItem) -> Session? { satisfiedMapping[item.id] }

    private func resultText(_ session: Session) -> String {
        var parts: [String] = []
        if let duration = session.durationSeconds { parts.append(Formatters.duration(duration)) }
        if session.distanceMeters > 0 {
            parts.append(Formatters.distance(session.distanceMeters))
            if session.workoutType == .run, let pace = session.paceSecondsPerKilometer {
                parts.append("\(paceLabel(pace))/km")
            }
        } else if session.targetValue > 0 { parts.append(session.displayTarget) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func paceVsTargetLine(item: PlanItem, session: Session) -> some View {
        if item.workoutType == .run {
            if let targetPace = item.targetSeconds {
                if let actualPace = session.paceSecondsPerKilometer {
                    let met = actualPace <= targetPace
                    HStack(spacing: 4) {
                        Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(met ? .green : .red)
                        Text(met ? "Beat \(paceLabel(targetPace))/km target" : "Missed \(paceLabel(targetPace))/km target")
                            .foregroundStyle(met ? .green : .red)
                    }
                    .font(.caption2)
                } else {
                    // Target was set but GPS distance too short to compute pace
                    Text("Target \(paceLabel(targetPace))/km · pace unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No Pace Target")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            if let targetSec = item.targetSeconds {
                if let duration = session.durationSeconds {
                    let met = duration <= targetSec
                    HStack(spacing: 4) {
                        Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(met ? .green : .red)
                        Text(met ? "Beat \(Formatters.duration(targetSec)) target" : "Missed \(Formatters.duration(targetSec)) target")
                            .foregroundStyle(met ? .green : .red)
                    }
                    .font(.caption2)
                } else {
                    Text("Target \(Formatters.duration(targetSec)) · time unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No Time Target")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func paceLabel(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Auto mode

    private func handleAutoModeExerciseComplete() {
        if currentItemIndex != nil || firstActivePending != nil {
            startAutoRest()
        } else {
            isPaused = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation { showWorkoutComplete = true }
        }
    }

    private func startAutoRest(from seconds: TimeInterval? = nil) {
        let start = seconds ?? TimeInterval(autoRestDuration)
        autoRestRemaining = start
        autoRestTask?.cancel()
        autoRestTask = Task { @MainActor in
            var remaining = start
            while remaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                remaining -= 1
                withAnimation { autoRestRemaining = remaining }
                if remaining > 0 && remaining <= 3 {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            }
            guard !Task.isCancelled else { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            autoRestRemaining = nil
            autoStartNextItem()
        }
    }

    private func skipAutoRest() {
        cancelAutoRest()
        autoStartNextItem()
    }

    private func cancelAutoRest() {
        autoRestTask?.cancel()
        autoRestTask = nil
        autoRestRemaining = nil
    }

    private func autoStartNextItem() {
        if let idx = currentItemIndex {
            startItem(orderedPlanItems[idx])
        } else if let first = firstActivePending {
            startPendingItem(first)
        }
    }
}

// MARK: - Reorder Sheet

fileprivate struct ReorderSheet: View {
    let frozenEntries: [ReorderEntry]
    let onDone: ([ReorderEntry]) -> Void

    @State private var items: [ReorderEntry]
    @Environment(\.dismiss) private var dismiss

    init(frozenEntries: [ReorderEntry], mutableEntries: [ReorderEntry], onDone: @escaping ([ReorderEntry]) -> Void) {
        self.frozenEntries = frozenEntries
        self.onDone = onDone
        _items = State(initialValue: mutableEntries)
    }

    var body: some View {
        NavigationStack {
            List {
                if !frozenEntries.isEmpty {
                    Section("Completed / In Progress") {
                        ForEach(frozenEntries) { entry in
                            Label(entry.displayName, systemImage: entry.systemImage)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(frozenEntries.isEmpty ? "Exercises" : "Up Next") {
                    ForEach(items) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.displayName)
                                .font(.headline)
                            Text(entry.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onMove { from, to in
                        items.move(fromOffsets: from, toOffset: to)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .contentMargins(.bottom, 80, for: .scrollContent)
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(items)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - Add Exercise Sheet

struct AddExerciseSheet: View {
    var routeName: String? = nil
    var hiddenBuiltinRawValues: String = ""
    var onRouteRun: (() -> Void)? = nil
    let onSelectBuiltin: (WorkoutItemType) -> Void
    let onSelectCustom: (CustomExercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CustomExercise.sortOrder) private var customExercises: [CustomExercise]

    private var visibleBuiltins: [WorkoutItemType] {
        let hidden = Set(hiddenBuiltinRawValues.split(separator: ",").map(String.init))
        return WorkoutItemType.allCases.filter { !hidden.contains($0.rawValue) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let routeName {
                    Section {
                        Button {
                            onRouteRun?()
                            dismiss()
                        } label: {
                            Label(routeName, systemImage: "flag.checkered.2.crossed")
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .padding(.vertical, 4)
                        }
                    } header: {
                        Text("GPS Route Run")
                    }
                }

                if !customExercises.isEmpty {
                    Section("My Exercises") {
                        ForEach(customExercises) { exercise in
                            Button {
                                onSelectCustom(exercise)
                                dismiss()
                            } label: {
                                Label(exercise.name, systemImage: exercise.iconName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 4)
                            }
                        }
                    }
                }

                Section(routeName != nil || !customExercises.isEmpty ? "Built-in Exercises" : "") {
                    ForEach(visibleBuiltins) { type in
                        Button {
                            onSelectBuiltin(type)
                            dismiss()
                        } label: {
                            Label(type.displayName, systemImage: type.systemImage)
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Route Run Setup

struct RouteRunSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var route: Route

    var presetMeasure: WorkoutMeasure? = nil
    var presetTarget: Double? = nil

    @State private var sessionMode: SessionMode = .laps
    @State private var targetLaps: Int = 1
    @State private var targetMeters: Double = 400
    @State private var navigatingToRecording = false
    @State private var didNavigate = false

    private var isPreset: Bool { presetMeasure != nil && presetTarget != nil }

    @AppStorage(lapPresetsKey)   private var lapPresetsStorage   = JSONStringArray<Int>(defaultLapPresets)
    @AppStorage(meterPresetsKey) private var meterPresetsStorage = JSONStringArray<Double>(defaultMeterPresets)

    private var lapPresets:   [Int]    { lapPresetsStorage.values.sorted() }
    private var meterPresets: [Double] { meterPresetsStorage.values.sorted() }

    var body: some View {
        List {
            Section {
                Map(initialPosition: .automatic, interactionModes: []) {
                    if route.definitionPoints.count >= 2 {
                        MapPolyline(coordinates: route.smoothedCoordinates(epsilon: routeDisplayEpsilon))
                            .stroke(Color.blue, lineWidth: 4)
                    }
                    if let start = route.startCoordinate {
                        Annotation("", coordinate: start) {
                            ZStack {
                                Circle().fill(Color(red: 0.145, green: 0.388, blue: 0.922)).frame(width: 20, height: 20).shadow(radius: 2)
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.white)
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
            }

            if isPreset {
                // Target was set by the plan — show it read-only, skip the picker
                Section {
                    HStack {
                        Label(Formatters.distance(route.distanceMeters), systemImage: "ruler")
                        Spacer()
                        Text("per lap").foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    HStack {
                        Label("Target", systemImage: "target")
                        Spacer()
                        Text(presetMeasure.map { $0.formatted(presetTarget ?? 0) } ?? "")
                            .fontWeight(.semibold)
                    }
                    .font(.callout)
                } header: {
                    Text("Run Target")
                }
            } else {
                Section {
                    HStack {
                        Label(Formatters.distance(route.distanceMeters), systemImage: "ruler")
                        Spacer()
                        Text("per lap").foregroundStyle(.secondary)
                    }
                    .font(.callout)

                    Picker("Mode", selection: $sessionMode) {
                        Text("Laps").tag(SessionMode.laps)
                        Text("Meters").tag(SessionMode.distance)
                    }
                    .pickerStyle(.segmented)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(sessionMode == .laps ? lapPresets : [], id: \.self) { n in
                                chip(label: "\(n)", isSelected: sessionMode == .laps && targetLaps == n) { targetLaps = n }
                            }
                            ForEach(sessionMode == .distance ? meterPresets : [], id: \.self) { m in
                                chip(label: Formatters.distance(m), isSelected: sessionMode == .distance && targetMeters == m) { targetMeters = m }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                } header: {
                    Text("Configure Run")
                }
            }

            Section {
                Button {
                    didNavigate = true
                    navigatingToRecording = true
                } label: {
                    Label("Go to Start Line", systemImage: "play.fill")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .foregroundStyle(.green)
                .listRowBackground(Color.green.opacity(0.12))
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { applyPresetIfNeeded() }
        .navigationDestination(isPresented: $navigatingToRecording) {
            SessionRecordingView(
                route: route,
                initialMode: sessionMode,
                initialTarget: sessionMode == .laps ? Double(targetLaps) : targetMeters
            )
        }
        .onChange(of: navigatingToRecording) { _, isNavigating in
            if !isNavigating && didNavigate { dismiss() }
        }
    }

    private func applyPresetIfNeeded() {
        guard let measure = presetMeasure, let target = presetTarget else { return }
        switch measure {
        case .meters, .yards:
            sessionMode = .distance
            targetMeters = target
        case .laps:
            sessionMode = .laps
            targetLaps = max(1, Int(target))
        default:
            break
        }
    }

    private func chip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.callout.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color(.systemFill), in: Capsule())
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Workout Complete Overlay

private struct ConfettiPiece: Identifiable {
    let id = UUID()
    let x: CGFloat
    let startY: CGFloat
    let width: CGFloat
    let height: CGFloat
    let color: Color
    let isCircle: Bool
    let delay: Double
    let duration: Double
    let endRotation: Double

    static func generate(count: Int = 60) -> [ConfettiPiece] {
        let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .pink, .teal, .cyan, .mint]
        return (0..<count).map { i in
            ConfettiPiece(
                x: CGFloat.random(in: -200...200),
                startY: CGFloat.random(in: -700...(-250)),
                width: CGFloat.random(in: 8...15),
                height: CGFloat.random(in: 10...20),
                color: colors.randomElement()!,
                isCircle: i % 4 == 0,
                delay: Double.random(in: 0...1.4),
                duration: Double.random(in: 1.8...2.8),
                endRotation: Double.random(in: -720...720)
            )
        }
    }
}

private struct WorkoutCompleteOverlay: View {
    let onDismiss: () -> Void

    @State private var pieces: [ConfettiPiece] = []
    @State private var isFalling = false
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            ForEach(pieces) { piece in
                Group {
                    if piece.isCircle {
                        Circle()
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                    }
                }
                .frame(width: piece.width, height: piece.height)
                .foregroundStyle(piece.color)
                .offset(x: piece.x, y: isFalling ? 900 : piece.startY)
                .rotationEffect(.degrees(isFalling ? piece.endRotation : 0))
                .animation(.linear(duration: piece.duration).delay(piece.delay), value: isFalling)
            }

            if showContent {
                VStack(spacing: 20) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.yellow)
                        .shadow(color: .orange.opacity(0.5), radius: 10)

                    VStack(spacing: 8) {
                        Text("Workout Complete!")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Tap to dismiss")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .onAppear {
            pieces = ConfettiPiece.generate()
            withAnimation(.spring(duration: 0.5)) { showContent = true }
            withAnimation(.easeOut(duration: 0.2)) { isFalling = true }
        }
        .task {
            try? await Task.sleep(for: .seconds(5))
            onDismiss()
        }
    }
}

// MARK: - Exercise Config Sheet

struct ExerciseConfigSheet: View {
    let type: WorkoutItemType
    let onAdd: (WorkoutMeasure, Double) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selectedMeasure: WorkoutMeasure
    @State private var targetValue: Double

    init(type: WorkoutItemType, onAdd: @escaping (WorkoutMeasure, Double) -> Void) {
        self.type = type
        self.onAdd = onAdd
        let measure = type.availableMeasures.first ?? .reps
        _selectedMeasure = State(initialValue: measure)
        _targetValue = State(initialValue: Self.defaultValue(for: measure))
    }

    private static func defaultValue(for measure: WorkoutMeasure) -> Double {
        switch measure {
        case .meters:  return 400
        case .yards:   return 400
        case .laps:    return 1
        case .reps:    return 10
        case .minutes: return 2
        }
    }

    private var presets: [Double] {
        switch selectedMeasure {
        case .meters:  return [50, 100, 200, 300, 400, 500, 800, 1000, 1500, 2000]
        case .yards:   return [55, 100, 200, 300, 400, 500]
        case .laps:    return [1, 2, 3, 4, 5, 6, 8, 10, 12, 15]
        case .reps:    return [5, 8, 10, 12, 15, 20, 25, 30, 40, 50]
        case .minutes: return [0.5, 1, 2, 3, 5, 10, 15]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                // Large value display
                VStack(spacing: 6) {
                    Text(selectedMeasure.formatted(targetValue))
                        .font(.system(size: 52, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: targetValue)
                    Text(type.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                // Measure picker (only when multiple options)
                if type.availableMeasures.count > 1 {
                    Picker("Unit", selection: $selectedMeasure) {
                        ForEach(type.availableMeasures, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedMeasure) { _, newMeasure in
                        targetValue = Self.defaultValue(for: newMeasure)
                    }
                }

                // Preset chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                targetValue = preset
                            } label: {
                                Text(selectedMeasure.formatted(preset))
                                    .font(.callout.bold())
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(
                                        targetValue == preset ? Color.blue : Color(.secondarySystemGroupedBackground),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(targetValue == preset ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 2)
                }

                Spacer()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add To Plan") {
                        onAdd(selectedMeasure, targetValue)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NavigationStack {
        SurgeSessionDetailView(
            surgeSession: SurgeSession(
                name: "Morning · Jun 20",
                date: Calendar.current.startOfDay(for: Date())
            )
        )
    }
    .modelContainer(for: SurgeSession.self, inMemory: true)
}
