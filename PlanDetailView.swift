//
//  PlanDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.startPlan) private var startPlan
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var plan: Plan

    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var allGroups: [PlanGroup]

    @State private var selectedRoute: Route? = nil
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingDeleteConfirm = false
    @State private var showingMoveToGroup = false

    private var canStart: Bool { selectedRoute != nil && !plan.items.isEmpty }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Route picker
                VStack(alignment: .leading, spacing: 10) {
                    detailSectionHeader("Choose a Route")

                    if routes.isEmpty {
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
                                ForEach(routes) { route in
                                    Button {
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Button {
                            renameText = plan.name
                            showingRename = true
                        } label: {
                            Label("Rename Plan", systemImage: "pencil")
                        }

                        if !allGroups.isEmpty {
                            Button {
                                showingMoveToGroup = true
                            } label: {
                                Label(plan.group == nil ? "Add to Group" : "Move to Group", systemImage: "folder")
                            }
                        }

                        if plan.group != nil {
                            Button {
                                plan.group = nil
                            } label: {
                                Label("Remove from Group", systemImage: "folder.badge.minus")
                            }
                        }

                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }

                    Button {
                        if let route = selectedRoute {
                            startPlan?(plan, route)
                        }
                    } label: {
                        Text("Start")
                            .fontWeight(.semibold)
                    }
                    .disabled(!canStart)
                }
            }
        }
        .alert("Rename Plan", isPresented: $showingRename) {
            TextField("Plan name", text: $renameText)
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { plan.name = t }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Plan?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(plan)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This plan and all its exercises will be permanently deleted.")
        }
        .sheet(isPresented: $showingMoveToGroup) {
            MovePlanToGroupSheet(plan: plan, groups: allGroups)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 16)
        }
    }

    // MARK: - Helpers

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
