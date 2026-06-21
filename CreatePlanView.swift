//
//  CreatePlanView.swift
//  surge15
//
//  Form for assembling a new Plan: a name plus a list of (route, target laps) items.
//

import SwiftUI
import SwiftData

struct CreatePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var name: String = ""
    @State private var draftItems: [DraftItem] = []

    struct DraftItem: Identifiable {
        let id = UUID()
        var route: Route?
        var targetLaps: Int = 1
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Plan name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section {
                    if draftItems.isEmpty {
                        Text("A plan needs at least one item. Tap **Add Item** to start.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($draftItems) { $item in
                            VStack(alignment: .leading, spacing: 8) {
                                Picker("Route", selection: $item.route) {
                                    Text("Pick a route").tag(nil as Route?)
                                    ForEach(routes) { route in
                                        Text(route.name).tag(route as Route?)
                                    }
                                }
                                Stepper("Laps: \(item.targetLaps)", value: $item.targetLaps, in: 1...20)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete { offsets in
                            draftItems.remove(atOffsets: offsets)
                        }
                        .onMove { from, to in
                            draftItems.move(fromOffsets: from, toOffset: to)
                        }
                    }
                    Button {
                        draftItems.append(DraftItem(route: routes.first))
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                    }
                    .disabled(routes.isEmpty)
                } header: {
                    Text("Workout Items")
                } footer: {
                    if routes.isEmpty {
                        Text("Create at least one route before building a plan.")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("New Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !draftItems.isEmpty { EditButton() }
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !trimmedName.isEmpty
            && !draftItems.isEmpty
            && draftItems.allSatisfy { $0.route != nil }
    }

    private func save() {
        let plan = Plan(name: trimmedName)
        for (i, draft) in draftItems.enumerated() {
            guard let route = draft.route else { continue }
            let item = PlanItem(order: i, targetLaps: draft.targetLaps, route: route)
            plan.items.append(item)
        }
        modelContext.insert(plan)
        dismiss()
    }
}

#Preview {
    CreatePlanView()
        .modelContainer(for: Plan.self, inMemory: true)
}
