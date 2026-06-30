//
//  PlanDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.startPlan) private var startPlan
    @Environment(\.modelContext) private var modelContext
    @Bindable var plan: Plan

    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var selectedRoute: Route? = nil
    @State private var noRouteSelected: Bool = false

    private var hasRunItems: Bool {
        plan.items.contains { $0.workoutType == .run }
    }

    private var canStart: Bool {
        (selectedRoute != nil || noRouteSelected) && !plan.items.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Route picker
                VStack(alignment: .leading, spacing: 10) {
                    detailSectionHeader(hasRunItems ? "Choose a Route" : "Route · Not Required")

                    if hasRunItems && routes.isEmpty {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("No routes yet — create one on the Routes tab first.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                if !hasRunItems {
                                    Button {
                                        noRouteSelected = true
                                        selectedRoute = nil
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("No Route")
                                                .font(.subheadline.weight(.semibold))
                                            Text("No runs in this plan")
                                                .font(.caption)
                                                .opacity(0.85)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            noRouteSelected ? Color.blue : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                        .foregroundStyle(noRouteSelected ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }

                                ForEach(routes) { route in
                                    Button {
                                        noRouteSelected = false
                                        selectedRoute = route
                                    } label: {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(route.name)
                                                .font(.subheadline.weight(.semibold))
                                            Text(Formatters.distance(route.distanceMeters))
                                                .font(.caption)
                                                .opacity(0.85)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(
                                            selectedRoute?.id == route.id ? Color.blue : Color(.secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        )
                                        .foregroundStyle(selectedRoute?.id == route.id ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)

                // Exercises timeline
                VStack(alignment: .leading, spacing: 10) {
                    detailSectionHeader("Exercises  ·  \(plan.items.count)")

                    if plan.sortedItems.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "plus.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("No exercises in this plan.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    } else {
                        let items = plan.sortedItems
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                                planTimelineRow(item: item, isLast: idx == items.count - 1)
                            }
                        }
                    }
                }
                .padding(.horizontal)

                Spacer().frame(height: 16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if !hasRunItems {
                noRouteSelected = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        plan.isFavorite.toggle()
                    } label: {
                        Image(systemName: plan.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(plan.isFavorite ? .red : .secondary)
                    }
                    Button {
                        startPlan?(plan, noRouteSelected ? nil : selectedRoute)
                    } label: {
                        Text("Start")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canStart)
                }
            }
        }
    }

    // MARK: - Timeline row

    private func planTimelineRow(item: PlanItem, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().strokeBorder(Color(.separator), lineWidth: 2)
                    Image(systemName: item.workoutType.systemImage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
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

            VStack(alignment: .leading, spacing: 3) {
                Text(item.workoutType.displayName)
                    .font(.headline)
                Text(item.displayTarget)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let ts = item.targetSeconds {
                    Text(item.workoutType == .run
                         ? "Target: \(paceLabel(ts))/km"
                         : "Target: \(Formatters.duration(ts))")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.85))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    // MARK: - Helpers

    private func paceLabel(_ secondsPerKm: Double) -> String {
        let total = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private func detailSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
            .padding(.bottom, 6)
    }
}

// MARK: - Move to Group sheet

struct MovePlanToGroupSheet: View {
    @Bindable var plan: Plan
    let groups: [PlanGroup]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if plan.group != nil {
                    Section {
                        Button {
                            plan.group = nil
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "tray")
                                    .frame(width: 28)
                                    .foregroundStyle(.secondary)
                                Text("Ungrouped")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if plan.group == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }

                Section("Groups") {
                    ForEach(groups) { group in
                        Button {
                            plan.group = group
                            dismiss()
                        } label: {
                            HStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(planGradients[group.cardGradientIndex % planGradients.count].linear)
                                    .frame(width: 28, height: 28)
                                Text(group.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if plan.group?.persistentModelID == group.persistentModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move to Group")
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

#Preview {
    NavigationStack {
        PlanDetailView(plan: Plan(name: "HYROX Simulation"))
    }
    .modelContainer(for: [Plan.self, Route.self], inMemory: true)
}
