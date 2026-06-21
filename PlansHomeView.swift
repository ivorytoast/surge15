//
//  PlansHomeView.swift
//  surge15
//
//  The Plan tab. Plans are reusable workout templates — pick one from the
//  Workout CTA to auto-create a surge session with the planned items.
//

import SwiftUI
import SwiftData

struct PlansHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @Query private var routes: [Route]
    @State private var showingCreatePlan = false
    /// Flashes the "create a route first" text yellow when the user taps the
    /// disabled + while there are no routes yet.
    @State private var nudgeHighlight = false

    var body: some View {
        NavigationStack {
            Group {
                if plans.isEmpty {
                    if routes.isEmpty {
                        noRoutesYetState
                    } else {
                        noPlansYetState
                    }
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
                        if routes.isEmpty {
                            nudge()
                        } else {
                            showingCreatePlan = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(plusColor)
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

    // MARK: - + button styling

    private var plusColor: Color {
        if routes.isEmpty { return .secondary }
        if plans.isEmpty { return .blue }
        return .accentColor
    }

    // MARK: - Empty states

    private var noRoutesYetState: some View {
        ContentUnavailableView {
            Label("No Plans Yet", systemImage: "list.clipboard")
        } description: {
            VStack(spacing: 8) {
                Text("How can you build a plan without knowing where to use it?")
                Text("Create a route first.")
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.yellow.opacity(nudgeHighlight ? 0.6 : 0))
                    )
                    .scaleEffect(nudgeHighlight ? 1.08 : 1.0)
            }
            .animation(.easeInOut(duration: 0.25), value: nudgeHighlight)
        }
    }

    private var noPlansYetState: some View {
        ContentUnavailableView {
            Label("No Plans Yet", systemImage: "list.clipboard")
        } description: {
            Text("Create your first plan with the blue + button above. Pre-build a workout once and reuse it whenever you tap the Workout button.")
        }
    }

    // MARK: - Plan rows

    private func row(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.name).font(.headline)
            HStack(spacing: 8) {
                Label("\(plan.items.count) item\(plan.items.count == 1 ? "" : "s")", systemImage: "list.bullet")
                if let totalLaps = totalLaps(plan), totalLaps > 0 {
                    Label("\(totalLaps) lap\(totalLaps == 1 ? "" : "s") total", systemImage: "flag.checkered")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func totalLaps(_ plan: Plan) -> Int? {
        let total = plan.items.reduce(0) { $0 + $1.targetLaps }
        return total > 0 ? total : nil
    }

    private func deletePlans(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(plans[index])
        }
    }

    // MARK: - Nudge

    private func nudge() {
        nudgeHighlight = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            nudgeHighlight = false
        }
    }
}

#Preview {
    PlansHomeView()
        .modelContainer(for: Plan.self, inMemory: true)
}
