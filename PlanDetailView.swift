//
//  PlanDetailView.swift
//  surge15
//
//  View/edit a plan: rename, view items (read-only), delete.
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.startPlan) private var startPlan
    @Bindable var plan: Plan
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
            if let startPlan, !plan.items.isEmpty {
                Section {
                    Button {
                        startPlan(plan)
                    } label: {
                        Label("Start This Plan", systemImage: "bolt.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .listRowBackground(Color.blue.opacity(0.15))
                }
            }

            Section("Name") {
                TextField("Plan name", text: $plan.name)
                    .textInputAutocapitalization(.words)
            }

            Section("Items") {
                if plan.items.isEmpty {
                    Text("This plan has no items.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(plan.sortedItems) { item in
                        itemRow(item)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Plan", systemImage: "trash")
                }
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete this plan?", isPresented: $showingDeleteConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(plan)
                dismiss()
            }
        } message: {
            Text("Surge sessions previously created from this plan will keep their data, but lose the link back to the template.")
        }
    }

    private func itemRow(_ item: PlanItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.workoutType.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.workoutType.displayName)
                    .font(.headline)
                Text(item.displayTarget)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PlanDetailView(plan: Plan(name: "HYROX Simulation"))
    }
    .modelContainer(for: Plan.self, inMemory: true)
}
