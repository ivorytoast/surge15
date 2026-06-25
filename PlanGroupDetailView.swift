//
//  PlanGroupDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanGroupDetailView: View {
    @Bindable var group: PlanGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var allGroups: [PlanGroup]

    @State private var showingCreatePlan = false

    // Plan actions (triggered by long-press on plan row)
    @State private var editingPlan: Plan? = nil
    @State private var recoloringPlan: Plan? = nil
    @State private var renamingPlan: Plan? = nil
    @State private var planRenameText = ""
    @State private var movingPlan: Plan? = nil
    @State private var deletingPlan: Plan? = nil

    // MARK: - Adaptive palette (mirrors PlansHomeView)
    private var isLight: Bool { colorScheme == .light }
    private var pageBackground: Color { isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094) }
    private var rowBackground: Color { isLight ? .white : Color(red: 0.055, green: 0.078, blue: 0.188) }
    private var headingColor: Color { isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white }
    private var rowIconColor: Color { isLight ? Color(red: 0.624, green: 0.690, blue: 0.831) : Color(red: 0.761, green: 0.804, blue: 0.894) }
    private var rowChevronColor: Color { isLight ? Color(red: 0.761, green: 0.804, blue: 0.894) : Color(red: 0.624, green: 0.690, blue: 0.831) }
    private var sectionLabelColor: Color { isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980) }

    private var sortedPlans: [Plan] {
        group.plans.sorted { $0.surgeSessions.count > $1.surgeSessions.count }
    }

    var body: some View {
        Group {
            if sortedPlans.isEmpty {
                emptyGroupState
            } else {
                ZStack {
                    pageBackground.ignoresSafeArea()
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(sortedPlans.enumerated()), id: \.element.id) { idx, plan in
                                NavigationLink(value: plan) {
                                    planRow(plan, isLast: idx == sortedPlans.count - 1)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { editingPlan = plan } label: {
                                        Label("Edit Plan", systemImage: "square.and.pencil")
                                    }
                                    Button { recoloringPlan = plan } label: {
                                        Label("Edit Color", systemImage: "paintpalette")
                                    }
                                    Button {
                                        planRenameText = plan.name
                                        renamingPlan = plan
                                    } label: {
                                        Label("Rename Plan", systemImage: "pencil")
                                    }
                                    Button { movingPlan = plan } label: {
                                        Label("Move to Group", systemImage: "folder")
                                    }
                                    Button(role: .destructive) {
                                        deletingPlan = plan
                                    } label: {
                                        Label("Delete Plan", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .background(rowBackground, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                    }
                }
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    Button {
                        group.isFavorite.toggle()
                    } label: {
                        Image(systemName: group.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(group.isFavorite ? .red : .secondary)
                    }
                    Button {
                        showingCreatePlan = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationDestination(for: Plan.self) { plan in
            PlanDetailView(plan: plan)
        }
        .sheet(isPresented: $showingCreatePlan) {
            CreatePlanView(presetGroup: group)
        }
        .sheet(item: $editingPlan) { plan in
            CreatePlanView(editingPlan: plan)
        }
        .sheet(item: $recoloringPlan) { plan in
            PlanColorPickerSheet(plan: plan)
        }
        .sheet(item: $movingPlan) { plan in
            MovePlanToGroupSheet(plan: plan, groups: allGroups)
        }
        .alert("Rename Plan", isPresented: Binding(
            get: { renamingPlan != nil },
            set: { if !$0 { renamingPlan = nil } }
        )) {
            TextField("Plan name", text: $planRenameText)
            Button("Save") {
                let t = planRenameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { renamingPlan?.name = t }
                renamingPlan = nil
            }
            Button("Cancel", role: .cancel) { renamingPlan = nil }
        }
        .alert("Delete Plan", isPresented: Binding(
            get: { deletingPlan != nil },
            set: { if !$0 { deletingPlan = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let plan = deletingPlan { modelContext.delete(plan) }
                deletingPlan = nil
            }
            Button("Cancel", role: .cancel) { deletingPlan = nil }
        } message: {
            Text("Are you sure you want to delete \"\(deletingPlan?.name ?? "")\"? This cannot be undone.")
        }
    }

    // MARK: - Plan row

    private func planRow(_ plan: Plan, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isLight ? Color(red: 0.878, green: 0.922, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(width: 36, height: 36)
                Text("\(plan.surgeSessions.count)")
                    .font(.headline.bold())
                    .foregroundStyle(sectionLabelColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(headingColor)
                Text("\(plan.items.count) exercise\(plan.items.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(rowIconColor)
            }

            Spacer()

            if plan.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundStyle(Color(red: 0.922, green: 0.302, blue: 0.400))
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(rowChevronColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !isLast {
                Color(isLight ? Color(red: 0.749, green: 0.859, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541))
                    .frame(height: 0.5)
                    .padding(.leading, 64)
            }
        }
    }

    // MARK: - Empty state

    private var emptyGroupState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No plans in this group yet.")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button {
                showingCreatePlan = true
            } label: {
                Label("Add First Plan", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}

#Preview {
    NavigationStack {
        PlanGroupDetailView(group: PlanGroup(name: "HYROX"))
    }
    .modelContainer(for: [PlanGroup.self, Plan.self, PlanItem.self], inMemory: true)
}
