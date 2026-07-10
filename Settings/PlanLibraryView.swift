//
//  PlanLibraryView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct PlanLibraryView: View {
    @Query(sort: \Plan.createdAt, order: .reverse) private var plans: [Plan]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    @State private var renamingPlan: Plan?
    @State private var newName: String = ""
    @State private var deletingPlan: Plan?

    var body: some View {
        List {
            ForEach(plans) { plan in
                HStack {
                    Button {
                        guard editMode?.wrappedValue != .active else { return }
                        renamingPlan = plan
                        newName = plan.name
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(plan.name)
                                    .foregroundStyle(.primary)
                                Text("\(plan.items.count) exercise\(plan.items.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if editMode?.wrappedValue != .active {
                                Image(systemName: "pencil")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                        }
                    }
                    if editMode?.wrappedValue == .active {
                        Button(role: .destructive) {
                            deletingPlan = plan
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel("Delete \(plan.name)")
                    }
                }
            }
        }
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .alert("Rename Plan", isPresented: Binding(
            get: { renamingPlan != nil },
            set: { if !$0 { renamingPlan = nil } }
        )) {
            TextField("Plan Name", text: $newName)
                .autocorrectionDisabled()
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { renamingPlan?.name = trimmed }
                renamingPlan = nil
            }
            Button("Cancel", role: .cancel) { renamingPlan = nil }
        }
        .alert("Delete Plan?", isPresented: Binding(
            get: { deletingPlan != nil },
            set: { if !$0 { deletingPlan = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let plan = deletingPlan { modelContext.delete(plan) }
                deletingPlan = nil
            }
            Button("Cancel", role: .cancel) { deletingPlan = nil }
        } message: {
            if let plan = deletingPlan {
                Text("\"\(plan.name)\" and all its exercises will be permanently deleted.")
            }
        }
    }
}
