//
//  WorkoutStarterSheet.swift
//  surge15
//
//  The unified sheet behind the middle "Workout" CTA. Lists Plans (templates),
//  today's existing Surge Sessions, and a "New Blank" fallback in one screen.
//

import SwiftUI
import SwiftData

struct WorkoutStarterSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @Query(sort: \SurgeSession.createdAt, order: .reverse) private var allSurgeSessions: [SurgeSession]

    let onSelect: (SurgeSession) -> Void

    var body: some View {
        NavigationStack {
            List {
                if !plans.isEmpty {
                    Section("Start from a Plan") {
                        ForEach(plans) { plan in
                            Button {
                                applyPlan(plan)
                            } label: {
                                planRow(plan)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !todaysSurgeSessions.isEmpty {
                    Section("Pick A Surge Session From Today") {
                        ForEach(todaysSurgeSessions) { surge in
                            Button {
                                onSelect(surge)
                            } label: {
                                surgeRow(surge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button {
                        createBlank()
                    } label: {
                        Label("New Surge Session", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .navigationTitle("Start Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var todaysSurgeSessions: [SurgeSession] {
        let now = Date()
        return allSurgeSessions.filter {
            Calendar.current.isDate($0.date, inSameDayAs: now)
        }
    }

    private func planRow(_ plan: Plan) -> some View {
        HStack {
            Image(systemName: "list.clipboard.fill")
                .foregroundStyle(.blue)
                .font(.title3)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.name).font(.headline)
                Text("\(plan.items.count) item\(plan.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func surgeRow(_ surge: SurgeSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(surge.name).font(.headline)
                HStack(spacing: 8) {
                    Text(surge.createdAt.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("\(surge.sessions.count) session\(surge.sessions.count == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func applyPlan(_ plan: Plan) {
        let now = Date()
        let surge = SurgeSession(
            name: plan.name,
            date: Calendar.current.startOfDay(for: now),
            createdAt: now
        )
        surge.plan = plan
        modelContext.insert(surge)
        onSelect(surge)
    }

    private func createBlank() {
        let now = Date()
        let surge = SurgeSession(
            name: SurgeSession.autoName(for: now),
            date: Calendar.current.startOfDay(for: now),
            createdAt: now
        )
        modelContext.insert(surge)
        onSelect(surge)
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            WorkoutStarterSheet(onSelect: { _ in })
        }
        .modelContainer(for: SurgeSession.self, inMemory: true)
}
