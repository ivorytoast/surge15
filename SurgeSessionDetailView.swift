//
//  SurgeSessionDetailView.swift
//  surge15
//
//  Shows one day's surge session: its editable name + the route Sessions
//  recorded under it. Designed to consolidate everything you did across
//  multiple routes/exercises in a single workout.
//

import SwiftUI
import SwiftData

struct SurgeSessionDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var surgeSession: SurgeSession
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            Section("Surge Session") {
                TextField("Name", text: $surgeSession.name)
                    .textInputAutocapitalization(.words)
                LabeledContent("Date", value: surgeSession.date.formatted(date: .complete, time: .omitted))
                LabeledContent("Started", value: surgeSession.createdAt.formatted(date: .omitted, time: .shortened))
                LabeledContent("Sessions", value: "\(surgeSession.sessions.count)")
                if let total = surgeSession.totalDurationSeconds {
                    LabeledContent("Total Active Time", value: Formatters.duration(total))
                }
                if surgeSession.totalDistanceMeters > 0 {
                    LabeledContent("Total Distance", value: Formatters.distance(surgeSession.totalDistanceMeters))
                }
            }

            if let plan = surgeSession.plan, !plan.items.isEmpty {
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

            Section("Sessions") {
                if surgeSession.sessions.isEmpty {
                    Text("No sessions yet. Start one from any route's detail page.")
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

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Surge Session", systemImage: "trash")
                }
            }
        }
        .navigationTitle(surgeSession.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this surge session?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(surgeSession)
                dismiss()
            }
        } message: {
            Text("This removes the surge session record. The route sessions inside will remain attached to their routes.")
        }
    }

    /// Greedy assignment: each planned item claims at most one recorded session
    /// (same route, at least the planned lap count). Sessions can only satisfy one item.
    private var satisfiedItemIDs: Set<PersistentIdentifier> {
        guard let plan = surgeSession.plan else { return [] }
        var satisfied = Set<PersistentIdentifier>()
        var claimed = Set<PersistentIdentifier>()
        for item in plan.sortedItems {
            guard let itemRoute = item.route else { continue }
            if let match = surgeSession.sessions.first(where: { session in
                !claimed.contains(session.id)
                && session.route?.id == itemRoute.id
                && session.targetLaps >= item.targetLaps
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
                Text(item.route?.name ?? "Unknown Route")
                    .font(.headline)
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? .secondary : .primary)
                Text("\(item.targetLaps) lap\(item.targetLaps == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.route?.name ?? "Unknown Route")
                .font(.headline)
            HStack(spacing: 10) {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                if let duration = session.durationSeconds {
                    Text("·")
                    Text(Formatters.duration(duration))
                }
                Text("·")
                Text("\(session.targetLaps) \(session.targetLaps == 1 ? "lap" : "laps")")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
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
