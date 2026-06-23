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
    let type: WorkoutItemType
    let measure: WorkoutMeasure
    let targetValue: Double

    var displayTarget: String {
        type == .run ? "Route run" : measure.formatted(targetValue)
    }
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
        switch self { case .planItem(let i): return i.workoutType.displayName; case .pending(let p): return p.type.displayName }
    }
    var systemImage: String {
        switch self { case .planItem(let i): return i.workoutType.systemImage; case .pending(let p): return p.type.systemImage }
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
    @State private var viewingSession: Session?
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

    private var isLive: Bool { surgeSession.isCurrent }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                workoutTimeline
                    .padding(.horizontal)
                    .padding(.top, isLive ? 8 : 0)

                if !isLive, let total = surgeSession.totalDurationSeconds {
                    summaryCard(total: total)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, isLive ? 100 : 24)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(surgeSession.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(navBarTintColor, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Group {
                    if isLive {
                        Text(Formatters.duration(elapsedActiveTime))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(titleColor)
                            .animation(.easeInOut(duration: 0.25), value: flashingGreen)
                            .animation(.easeInOut(duration: 0.2), value: isPaused)
                    } else {
                        Text(surgeSession.name)
                            .font(.headline)
                    }
                }
            }
            if isLive {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddExercise = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isLive { actionBar }
        }
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
            if let type = pendingConfigType {
                configuringExercise = type
                pendingConfigType = nil
            }
        }) {
            AddExerciseSheet(
                routeName: surgeSession.route?.name,
                onRouteRun: {
                    // Route runs configure in RouteRunSetupView — queue with defaults
                    pendingAdHocItems.append(PendingExercise(type: .run, measure: .laps, targetValue: 1))
                    showingAddExercise = false
                },
                onSelect: { type in
                    // All other exercises show a config sheet first
                    pendingConfigType = type
                    showingAddExercise = false
                }
            )
        }
        .sheet(item: $configuringExercise) { type in
            ExerciseConfigSheet(type: type) { measure, value in
                pendingAdHocItems.append(PendingExercise(type: type, measure: measure, targetValue: value))
            }
        }
        .sheet(item: $recordingExercise, onDismiss: {
            recordingMeasure = nil
            recordingTarget = nil
        }) { type in
            ExerciseRecordingView(
                workoutType: type,
                measure: recordingMeasure,
                targetValue: recordingTarget,
                surgeSession: surgeSession
            )
        }
        .sheet(item: $viewingSession) { session in
            NavigationStack { SessionDetailView(session: session) }
        }
        .sheet(isPresented: $showingReorder) {
            let frozen = orderedPlanItems.prefix(frozenCount).map { ReorderEntry.planItem($0) }
            ReorderSheet(
                frozenEntries: Array(frozen),
                mutableEntries: mutableFutureEntries,
                onDone: applyReorder
            )
        }
        .navigationDestination(item: $routeForSetup) { route in
            RouteRunSetupView(route: route)
        }
        .alert("End this workout?", isPresented: $showingEndConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                surgeSession.endedAt = Date()
                dismiss()
            }
        } message: {
            Text("You can still view this workout in the calendar.")
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
                } else if skipped {
                    Text("Skipped")
                        .font(.caption)
                        .foregroundStyle(Color(.tertiaryLabel))
                } else {
                    Text(item.displayTarget)
                        .font(.caption)
                        .foregroundStyle(isCurrent ? Color.primary.opacity(0.6) : Color.secondary)
                }

                if done, let s = matched {
                    Button { viewingSession = s } label: {
                        Text("View details")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
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
                Text((session.workoutType ?? .run).displayName)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(resultText(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button { viewingSession = session } label: {
                    Text("View details")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
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
                Text(exercise.type.displayName)
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
        pendingAdHocItems.removeAll { $0.id == exercise.id }
        if exercise.type == .run, let route = surgeSession.route {
            routeForSetup = route
        } else {
            recordingMeasure = exercise.measure
            recordingTarget = exercise.targetValue
            recordingExercise = exercise.type
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
        HStack(spacing: 0) {
            // Back — undo last skip
            actionButton(icon: "arrow.uturn.backward.circle", label: "Back", color: .secondary) {
                goBack()
            }
            .disabled(skippedItems.isEmpty && skippedPendingIDs.isEmpty)

            // Skip — advance past current item
            actionButton(icon: "forward.fill", label: "Skip", color: .secondary) {
                skipCurrentItem()
            }
            .disabled(currentItemIndex == nil && firstActivePending == nil)

            // Start — launch the current exercise (center, largest)
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

            // Pause / Go toggle — switches label and icon based on state
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
        .padding(.top, 10)
        .padding(.bottom, 6)
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
                    Image(systemName: (session.workoutType ?? .run).systemImage)
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text((session.workoutType ?? .run).displayName).font(.headline)
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
    }

    private func startItem(_ item: PlanItem) {
        if item.workoutType == .run, let route = surgeSession.route {
            routeForSetup = route
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
        if session.distanceMeters > 0 { parts.append(Formatters.distance(session.distanceMeters)) }
        else if session.targetValue > 0 { parts.append(session.displayTarget) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
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
    var onRouteRun: (() -> Void)? = nil
    let onSelect: (WorkoutItemType) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let routeName {
                    Section {
                        Button {
                            onRouteRun?()
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
                Section(routeName != nil ? "Other Exercises" : "") {
                    ForEach(WorkoutItemType.allCases) { type in
                        Button {
                            onSelect(type)
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

    @State private var sessionMode: SessionMode = .laps
    @State private var targetLaps: Int = 1
    @State private var targetMeters: Double = 400
    @State private var navigatingToRecording = false
    @State private var didNavigate = false

    private let lapPresets    = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 20, 25, 50, 100]
    private let meterPresets: [Double] = [1, 5, 10, 20, 40, 50, 75, 100, 125, 150, 200, 250,
                                          300, 350, 400, 450, 500, 550, 600, 650, 700, 750,
                                          800, 850, 900, 950, 1000]

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
                                Circle().fill(.white).frame(width: 20, height: 20).shadow(radius: 2)
                                Image(systemName: "flag.fill")
                                    .foregroundStyle(.green)
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
