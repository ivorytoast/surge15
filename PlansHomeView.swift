//
//  PlansHomeView.swift
//  surge15
//
//  The Plan tab. Plans are reusable, route-agnostic workout templates.
//  You pick a route when you actually start a plan, not when creating it.
//

import SwiftUI
import SwiftData

struct PlansHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @State private var showingCreatePlan = false

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    noPlansYetState
                } else {
                    List {
                        ForEach(plans) { plan in
                            NavigationLink(value: plan) {
                                row(plan)
                            }
                        }
                        .onDelete(perform: deletePlans)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreatePlan = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create Plan")
                }
            }
            .navigationDestination(for: Plan.self) { plan in
                PlanDetailView(plan: plan)
            }
            .sheet(isPresented: $showingCreatePlan) {
                CreatePlanView()
            }
        }
    }

    // MARK: - Empty state

    private var noPlansYetState: some View {
        ContentUnavailableView {
            Label("No Plans Yet", systemImage: "list.clipboard")
        } description: {
            Text("Build a reusable workout once with the + button above. Pick a route when you're ready to start.")
        }
    }

    // MARK: - Plan row

    private func row(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.name).font(.headline)
            HStack(spacing: 8) {
                Label("\(plan.items.count) item\(plan.items.count == 1 ? "" : "s")", systemImage: "list.bullet")
                if let summary = typeSummary(plan) {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(summary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// E.g. "Run · Lunge · BBJ" from the sorted items.
    private func typeSummary(_ plan: Plan) -> String? {
        guard !plan.items.isEmpty else { return nil }
        let names: [String] = plan.sortedItems.map { $0.workoutType.shortName }
        return names.joined(separator: " · ")
    }

    private func deletePlans(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(plans[index])
        }
    }
}

#Preview {
    PlansHomeView()
        .modelContainer(for: Plan.self, inMemory: true)
}
