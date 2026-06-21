//
//  SurgeSessionDetailView.swift
//  surge15
//
//  Two visual modes:
//  - Running (surgeSession.isCurrent): minimal — live elapsed timer + sessions + End.
//  - Past:    rich — full stats + sessions + delete.
//

import SwiftUI
import SwiftData

struct SurgeSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var surgeSession: SurgeSession
    @State private var showingDeleteConfirm = false
    @State private var showingEndConfirm = false
    @State private var recordingExercise: WorkoutItemType?
    /// Drives the live elapsed timer while the surge session is running.
    @State private var now = Date()

    private var isLive: Bool { surgeSession.isCurrent }

    var body: some View {
        List {
            if isLive {
                liveContent
            } else {
                pastContent
            }
        }
        .navigationTitle(surgeSession.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(item: $recordingExercise) { type in
            ExerciseRecordingView(workoutType: type, surgeSession: surgeSession)
        }
        .alert("Delete this surge session?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(surgeSession)
                dismiss()
            }
        } message: {
            Text("This removes the surge session record. The route sessions inside will remain attached to their routes.")
        }
        .alert("End this workout?", isPresented: $showingEndConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("End", role: .destructive) {
                surgeSession.endedAt = Date()
            }
        } message: {
            Text("Starting a new workout after this will create a fresh surge session. You can still view this one later in the calendar.")
        }
    }

    // MARK: - Live (currently running) layout

    @ViewBuilder
    private var liveContent: some View {
        Section {
            Button(role: .destructive) {
                showingEndConfirm = true
            } label: {
                Label("End Session", systemImage: "stop.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(Color.red.opacity(0.12))
        }

        Section {
            VStack(spacing: 6) {
                Text(Formatters.duration(elapsedSinceStart))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("elapsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if surgeSession.totalDistanceMeters > 0 {
                    Text("\(Formatters.distance(surgeSession.totalDistanceMeters)) total")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .listRowBackground(Color.clear)
        }

        Section {
            ForEach(WorkoutItemType.allCases) { type in
                Button { startExercise(type) } label: {
                    Label(type.displayName, systemImage: type.systemImage)
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .foregroundStyle(.green)
                .listRowBackground(Color.green.opacity(0.12))
            }
        } header: {
            Text("Add Exercise")
        }

        if let plan = surgeSession.plan, !plan.items.isEmpty {
            plannedSection(plan)
        }

        sessionsSection

        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Past layout

    @ViewBuilder
    private var pastContent: some View {
        Section {
            VStack(spacing: 4) {
                Text(Formatters.duration(surgeSession.totalDurationSeconds ?? 0))
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("total active time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if surgeSession.totalDistanceMeters > 0 {
                    Text(Formatters.distance(surgeSession.totalDistanceMeters))
                        .font(.title3.bold())
                        .monospacedDigit()
                        .padding(.top, 8)
                    Text("total distance")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .listRowBackground(Color.clear)
        }

        if let plan = surgeSession.plan, !plan.items.isEmpty {
            plannedSection(plan)
        }

        sessionsSection

        Section {
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Shared sections

    private func plannedSection(_ plan: Plan) -> some View {
        Section {
            ForEach(plan.sortedItems) { item in
                plannedRow(item)
            }
        } header: {
            HStack {
                Text("Planned")
                Spacer()
                Text("\(satisfiedItemIDs.count) / \(plan.items.count) done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sessionsSection: some View {
        Section("Sessions") {
            if surgeSession.sessions.isEmpty {
                Text(isLive
                     ? "Add your first exercise using the buttons above."
                     : "No exercises were recorded.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(surgeSession.sortedSessions) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        sessionRow(session)
                    }
                }
                .onDelete(perform: deleteSessions)
            }
        }
    }

    // MARK: - Derived

    private var elapsedSinceStart: TimeInterval {
        now.timeIntervalSince(surgeSession.createdAt)
    }

    /// Greedy assignment: each Run item claims at most one recorded session that
    /// meets or exceeds its target. Non-run items (Lunge, BBJ) can't be auto-satisfied yet.
    private var satisfiedItemIDs: Set<PersistentIdentifier> {
        guard let plan = surgeSession.plan else { return [] }
        var satisfied = Set<PersistentIdentifier>()
        var claimed = Set<PersistentIdentifier>()
        for item in plan.sortedItems {
            guard item.workoutType == .run else { continue }
            if let match = surgeSession.sessions.first(where: { session in
                guard !claimed.contains(session.id) else { return false }
                switch item.measure {
                case .meters, .yards: return session.distanceMeters >= item.targetValue
                case .laps:           return Double(session.targetLaps) >= item.targetValue
                case .reps, .minutes: return false
                }
            }) {
                satisfied.insert(item.id)
                claimed.insert(match.id)
            }
        }
        return satisfied
    }

    private func plannedRow(_ item: PlanItem) -> some View {
        let isDone = satisfiedItemIDs.contains(item.id)
        return HStack(spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.workoutType.displayName)
                    .font(.headline)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text(item.displayTarget)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        HStack(spacing: 12) {
            Image(systemName: session.workoutType.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.workoutType.displayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(session.displayTarget)
                    if let duration = session.durationSeconds {
                        Text("·")
                        Text(Formatters.duration(duration))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func startExercise(_ type: WorkoutItemType) {
        recordingExercise = type
    }

    private func deleteSessions(_ offsets: IndexSet) {
        let sorted = surgeSession.sortedSessions
        for index in offsets {
            modelContext.delete(sorted[index])
        }
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
