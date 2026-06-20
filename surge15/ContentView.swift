import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]
    @State private var showingCreateRoute = false

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty {
                    ContentUnavailableView {
                        Label("No Routes Yet", systemImage: "figure.run")
                    } description: {
                        Text("Create your first loop. Walk or run it once so the app learns its shape, then come back here to train on it.")
                    } actions: {
                        Button {
                            showingCreateRoute = true
                        } label: {
                            Label("Create Route", systemImage: "plus")
                                .font(.headline)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(routes) { route in
                            NavigationLink(value: route) {
                                routeRow(route)
                            }
                        }
                        .onDelete(perform: deleteRoutes)
                    }
                }
            }
            .navigationTitle("Routes")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateRoute = true
                    } label: {
                        Label("Create Route", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: Route.self) { route in
                RouteDetailView(route: route)
            }
            .sheet(isPresented: $showingCreateRoute) {
                CreateRouteView()
            }
        }
    }

    private func routeRow(_ route: Route) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name).font(.headline)
            HStack(spacing: 8) {
                Label(Formatters.distance(route.distanceMeters), systemImage: "ruler")
                Label("\(route.sessions.count) sessions", systemImage: "figure.run")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func deleteRoutes(_ offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(routes[index])
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Route.self, inMemory: true)
}
