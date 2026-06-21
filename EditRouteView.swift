//
//  EditRouteView.swift
//  surge15
//
//  Scoped to two operations: rename and delete.
//  Editing the GPS path or segments is intentionally out of scope.
//

import SwiftUI
import SwiftData

struct EditRouteView: View {
    @Bindable var route: Route
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var showingDeleteConfirm = false

    init(route: Route) {
        self._route = Bindable(wrappedValue: route)
        self._name = State(initialValue: route.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Route name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Stats") {
                    LabeledContent("Distance", value: Formatters.distance(route.distanceMeters))
                    LabeledContent("Segments", value: "\(max(route.segments.count, 1))")
                    LabeledContent("Sessions", value: "\(route.sessions.count)")
                    LabeledContent("Created", value: route.createdAt.formatted(date: .abbreviated, time: .shortened))
                }

                Section {
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Route", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Edit Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedName.isEmpty)
                }
            }
            .alert("Delete this route?", isPresented: $showingDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    modelContext.delete(route)
                    dismiss()
                }
            } message: {
                Text("This deletes the route and all of its \(route.sessions.count) session\(route.sessions.count == 1 ? "" : "s"). This can't be undone.")
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save() {
        route.name = trimmedName
        dismiss()
    }
}

#Preview {
    EditRouteView(route: Route(name: "Backyard 1k"))
        .modelContainer(for: Route.self, inMemory: true)
}
