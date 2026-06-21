//
//  PlanDetailView.swift
//  surge15
//
//  View/edit a plan: rename, view items (read-only for now), delete.
//

import SwiftUI
import SwiftData

struct PlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var plan: Plan
    @State private var showingDeleteConfirm = false

    var body: some View {
        List {
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
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.route?.name ?? "Unknown Route").font(.headline)
                Text("\(item.targetLaps) lap\(item.targetLaps == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

#Preview {
    NavigationStack {
        PlanDetailView(plan: Plan(name: "Compromised running"))
    }
    .modelContainer(for: Plan.self, inMemory: true)
}
