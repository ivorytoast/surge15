//
//  PlanGroupDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanGroupDetailView: View {
    @Bindable var group: PlanGroup
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingCreatePlan = false
    @State private var showingRename = false
    @State private var renameText = ""
    @State private var showingDeleteConfirm = false

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        Group {
            if group.sortedPlans.isEmpty {
                emptyGroupState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(group.sortedPlans) { plan in
                            NavigationLink(value: plan) {
                                PlanCardView(plan: plan)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
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
                    Menu {
                        Button {
                            renameText = group.name
                            showingRename = true
                        } label: {
                            Label("Rename Group", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            showingDeleteConfirm = true
                        } label: {
                            Label("Delete Group", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .alert("Rename Group", isPresented: $showingRename) {
            TextField("Group name", text: $renameText)
            Button("Save") {
                let t = renameText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { group.name = t }
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Group?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                modelContext.delete(group)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Plans in this group will become ungrouped.")
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
