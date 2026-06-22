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
import MapKit

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
        .navigationDestination(for: Route.self) { route in
            RouteRunSetupView(route: route)
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

        if let route = surgeSession.route {
            Section {
                NavigationLink(value: route) {
                    Label("Route Run", systemImage: "flag.checkered.2.crossed")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                }
                .foregroundStyle(.blue)
                .listRowBackground(Color.blue.opacity(0.12))
            } header: {
                Text("GPS · \(route.name)")
            }
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
            Image(systemName: (session.workoutType ?? .run).systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text((session.workoutType ?? .run).displayName)
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
                    Text("per lap")
                        .foregroundStyle(.secondary)
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
                            chip(label: "\(n)", isSelected: sessionMode == .laps && targetLaps == n) {
                                targetLaps = n
                            }
                        }
                        ForEach(sessionMode == .distance ? meterPresets : [], id: \.self) { m in
                            chip(label: Formatters.distance(m), isSelected: sessionMode == .distance && targetMeters == m) {
                                targetMeters = m
                            }
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
            if !isNavigating && didNavigate {
                dismiss()
            }
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
