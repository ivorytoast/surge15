//
//  GroupLibraryView.swift
//  surge15
//

import SwiftUI
import SwiftData

// MARK: - Group list

struct GroupLibraryView: View {
    @Query(sort: \PlanGroup.createdAt, order: .reverse) private var groups: [PlanGroup]

    var body: some View {
        List {
            ForEach(groups) { group in
                NavigationLink {
                    GroupEditView(group: group)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(planGradients[group.cardGradientIndex % planGradients.count].linear)
                            .frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name)
                            Text("\(group.plans.count) plan\(group.plans.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Groups")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Group edit detail

struct GroupEditView: View {
    @Bindable var group: PlanGroup
    @Query(sort: \Plan.createdAt, order: .reverse) private var allPlans: [Plan]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingDeleteConfirm = false

    var body: some View {
        Form {
            Section {
                previewCard
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("Name") {
                TextField("Group Name", text: $group.name)
                    .textInputAutocapitalization(.words)
                    .font(.headline)
                    .autocorrectionDisabled()
            }

            Section("Color") {
                GradientPickerView(selectedIndex: $group.cardGradientIndex)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            Section {
                if allPlans.isEmpty {
                    Text("No plans yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allPlans) { plan in
                        Button {
                            if plan.group?.persistentModelID == group.persistentModelID {
                                plan.group = nil
                            } else {
                                plan.group = group
                            }
                        } label: {
                            HStack {
                                Text(plan.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if plan.group?.persistentModelID == group.persistentModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Plans")
            } footer: {
                Text("Tap to add or remove plans from this group. A plan can only belong to one group at a time.")
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Text("Delete Group")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            } footer: {
                Text("Plans in this group will not be deleted — they'll simply be unassigned.")
            }
        }
        .navigationTitle(group.name.isEmpty ? "Edit Group" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Group?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(group)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(group.name)\" will be removed. Its plans will be kept but unassigned from this group.")
        }
    }

    private var previewCard: some View {
        ZStack(alignment: .bottomLeading) {
            planGradients[group.cardGradientIndex % planGradients.count].linear
            LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                Image(systemName: "folder.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.75))
                Text(group.name.isEmpty ? "Group Name" : group.name)
                    .font(.title2.bold())
                    .foregroundStyle(group.name.isEmpty ? .white.opacity(0.4) : .white)
                    .lineLimit(1)
                let count = group.plans.count
                Text("\(count) plan\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 150)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .animation(.easeInOut(duration: 0.2), value: group.cardGradientIndex)
        .animation(.easeInOut(duration: 0.1), value: group.name)
    }
}
