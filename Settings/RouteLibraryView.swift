//
//  RouteLibraryView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct RouteLibraryView: View {
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @Environment(\.modelContext) private var modelContext

    @State private var renamingRoute: Route?
    @State private var newName: String = ""
    @State private var deletingRoute: Route?

    var body: some View {
        List {
            ForEach(routes) { route in
                Button {
                    renamingRoute = route
                    newName = route.name
                } label: {
                    HStack {
                        Text(route.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                }
            }
            .onDelete { indexSet in
                indexSet.forEach { deletingRoute = routes[$0] }
            }
        }
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            EditButton()
        }
        .alert("Rename Route", isPresented: Binding(
            get: { renamingRoute != nil },
            set: { if !$0 { renamingRoute = nil } }
        )) {
            TextField("Route Name", text: $newName)
                .autocorrectionDisabled()
            Button("Save") {
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { renamingRoute?.name = trimmed }
                renamingRoute = nil
            }
            Button("Cancel", role: .cancel) { renamingRoute = nil }
        }
        .alert("Delete Route?", isPresented: Binding(
            get: { deletingRoute != nil },
            set: { if !$0 { deletingRoute = nil } }
        )) {
            Button("Delete", role: .destructive) {
                if let route = deletingRoute { modelContext.delete(route) }
                deletingRoute = nil
            }
            Button("Cancel", role: .cancel) { deletingRoute = nil }
        } message: {
            if let route = deletingRoute {
                Text("\"\(route.name)\" and all its recorded sessions will be permanently deleted.")
            }
        }
    }
}
