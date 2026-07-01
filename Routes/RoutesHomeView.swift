//
//  RoutesHomeView.swift
//  surge15
//

import SwiftUI
import SwiftData
import CoreLocation
import MapKit

extension Route: Favoritable {}

// MARK: - View mode

enum HomeViewMode: String, CaseIterable, Identifiable {
    case map, list

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .map: return "map.fill"
        case .list: return "list.bullet"
        }
    }

    var label: String {
        switch self {
        case .map: return "Map"
        case .list: return "List"
        }
    }
}

// MARK: - Cluster types

/// A group of routes whose start points fall within the cluster threshold of each other.
struct RouteCluster: Identifiable {
    let routes: [Route]
    let coordinate: CLLocationCoordinate2D

    var id: String {
        routes.map { String(describing: $0.id) }.sorted().joined(separator: "|")
    }

    var isMulti: Bool { routes.count > 1 }
}

/// Wrapper so the cluster selection can drive `.sheet(item:)`.
struct RouteClusterSelection: Identifiable {
    let id = UUID()
    let routes: [Route]
}

/// Maximum number of characters displayed in compact row layouts before truncation.
let routeNameRowCharLimit = 16

func truncatedRouteName(_ name: String, limit: Int = routeNameRowCharLimit) -> String {
    name.count <= limit ? name : String(name.prefix(limit)) + "…"
}

// MARK: - RoutesHomeView

struct RoutesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var showingCreateRoute = false

    @State private var viewMode: HomeViewMode = .map
    @State private var tracker = LocationTracker()
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var didCenterOnUser = false

    // Peek sheet + post-dismiss navigation
    @State private var peekRoute: Route?
    @State private var clusterPeek: RouteClusterSelection?
    @State private var pendingPeek: Route?
    @State private var editingRoute: Route?
    @State private var deletingRoute: Route?
    @State private var path = NavigationPath()

    // "Go from map" flow — peek's Go button skips the detail view and jumps
    // straight into SessionRecordingView. The surge session is created only when
    // the user actually taps Start inside that view.
    @State private var goRoute: Route?
    @State private var goMode: SessionMode = .laps
    @State private var goTarget: Double = 1.0
    @State private var navigatingToRecording = false

    // Nearest-route suggestion bubble
    @State private var suggestionDismissed = false

    private static let defaultRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.5, longitude: -98.35),
        latitudinalMeters: 5_000_000,
        longitudinalMeters: 5_000_000
    )

    private let homeZoomMeters: CLLocationDistance = 3000
    private let clusterThresholdMeters: CLLocationDistance = 100

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if routes.isEmpty {
                    emptyState
                } else {
                    switch viewMode {
                    case .map: mapHome
                    case .list: listHome
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay {
                if let route = peekRoute {
                    ZStack {
                        Color.black.opacity(0.35)
                            .ignoresSafeArea()
                            .onTapGesture { peekRoute = nil }
                        RoutePeekSheet(
                            route: route,
                            onUse: { mode, target in
                                goRoute = route
                                goMode = mode
                                goTarget = target
                                peekRoute = nil
                                navigatingToRecording = true
                            }
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .animation(.easeInOut(duration: 0.18), value: peekRoute != nil)
            .navigationDestination(isPresented: $navigatingToRecording) {
                if let route = goRoute {
                    SessionRecordingView(route: route, initialMode: goMode, initialTarget: goTarget)
                }
            }
            .sheet(item: $clusterPeek, onDismiss: handleClusterDismiss) { selection in
                ClusterSheet(
                    routes: selection.routes,
                    onSelect: { route in
                        pendingPeek = route
                        clusterPeek = nil
                    }
                )
            }
            .sheet(item: $editingRoute) { route in
                EditRouteView(route: route)
            }
            .alert("Delete Route", isPresented: Binding(
                get: { deletingRoute != nil },
                set: { if !$0 { deletingRoute = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let route = deletingRoute { modelContext.delete(route) }
                    deletingRoute = nil
                }
                Button("Cancel", role: .cancel) { deletingRoute = nil }
            } message: {
                Text("Are you sure you want to delete \"\(deletingRoute?.name ?? "")\"? This cannot be undone.")
            }
            .sheet(isPresented: $showingCreateRoute) {
                CreateRouteView()
            }
            .onAppear {
                tracker.requestAuthorization()
                tracker.requestSingleLocation()
            }
            .onChange(of: tracker.recordedLocations.count) { _, _ in
                centerOnUserIfNeeded()
            }
        }
    }

    // MARK: - Deferred sheet→navigation handoff

    private func handleClusterDismiss() {
        if let pending = pendingPeek {
            peekRoute = pending
            pendingPeek = nil
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !routes.isEmpty {
                Button {
                    viewMode = viewMode == .map ? .list : .map
                } label: {
                    Image(systemName: viewMode == .map ? "list.bullet" : "map.fill")
                }
                .accessibilityLabel(viewMode == .map ? "Switch to list view" : "Switch to map view")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if viewMode == .map && !routes.isEmpty {
                Button {
                    recenterOnUser()
                } label: {
                    Image(systemName: "location.fill")
                }
                .accessibilityLabel("Center on my location")
                .disabled(isLocationUnavailable)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingCreateRoute = true
            } label: {
                Image(systemName: "plus")
                    .foregroundStyle(routes.isEmpty ? Color.blue : Color.accentColor)
            }
            .accessibilityLabel("Create Route")
        }
    }

    private func recenterOnUser() {
        didCenterOnUser = false
        tracker.requestSingleLocation()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Routes Yet", systemImage: "figure.run")
        } description: {
            Text("Create your first route with the blue + button above. Walk or run your personal track once so the app learns its shape.")
        }
    }

    // MARK: - Map mode

    private var mapHome: some View {
        ZStack(alignment: .bottom) {
            Map(position: $cameraPosition) {
                ForEach(clusters) { cluster in
                    Annotation(annotationTitle(for: cluster), coordinate: cluster.coordinate) {
                        Button {
                            tapped(cluster)
                        } label: {
                            if cluster.isMulti {
                                clusterPin(count: cluster.routes.count)
                            } else {
                                startPin
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapCompass()
            }
            .ignoresSafeArea(edges: .bottom)

            if isLocationUnavailable {
                deniedOverlay
            }

            if isAcquiringGPS {
                VStack {
                    acquiringGPSBanner
                    Spacer()
                }
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            nearestRouteSuggestion
        }
        .animation(.easeInOut(duration: 0.3), value: isAcquiringGPS)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: shouldShowSuggestion)
    }

    private var isAcquiringGPS: Bool {
        userCoordinate == nil &&
        (tracker.authorizationStatus == .authorizedWhenInUse ||
         tracker.authorizationStatus == .authorizedAlways)
    }

    private var acquiringGPSBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.85)
                .tint(.primary)
            Text("Acquiring GPS Location")
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    // MARK: - Nearest-route suggestion

    private var shouldShowSuggestion: Bool {
        !suggestionDismissed && peekRoute == nil && nearestRoute != nil && !isLocationUnavailable
    }

    private var nearestRoute: Route? {
        guard let user = userCoordinate else { return nil }
        return routes.min {
            ($0.startCoordinate?.distance(to: user) ?? .infinity) <
            ($1.startCoordinate?.distance(to: user) ?? .infinity)
        }
    }

    @ViewBuilder
    private var nearestRouteSuggestion: some View {
        if shouldShowSuggestion, let route = nearestRoute {
            Button {
                peekRoute = route
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                        .symbolEffect(.pulse)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Nearest Route")
                            .font(.caption2.bold())
                            .textCase(.uppercase)
                            .foregroundStyle(.secondary)
                        Text(route.name)
                            .font(.headline)
                        if let user = userCoordinate, let start = route.startCoordinate {
                            Text("\(Formatters.distance(start.distance(to: user))) away · tap to begin")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        withAnimation { suggestionDismissed = true }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.14), radius: 14, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func annotationTitle(for cluster: RouteCluster) -> String {
        if cluster.isMulti {
            return "\(cluster.routes.count) routes"
        }
        return cluster.routes.first?.name ?? ""
    }

    private func tapped(_ cluster: RouteCluster) {
        if cluster.isMulti {
            clusterPeek = RouteClusterSelection(routes: cluster.routes)
        } else if let route = cluster.routes.first {
            peekRoute = route
        }
    }

    private var startPin: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 34, height: 34)
                .shadow(radius: 2)
            Image(systemName: "flag.fill")
                .foregroundStyle(.green)
                .font(.system(size: 16, weight: .bold))
        }
    }

    private func clusterPin(count: Int) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 48, height: 48)
                .shadow(radius: 3)
            Circle()
                .fill(.green)
                .frame(width: 40, height: 40)
            Text("\(count)")
                .foregroundStyle(.white)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .monospacedDigit()
        }
    }

    private var isLocationUnavailable: Bool {
        tracker.authorizationStatus == .denied || tracker.authorizationStatus == .restricted
    }

    private var deniedOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                Text("Location Unavailable")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Without your location, the map can't show where you are or pin your routes. Switch to the list view to see all your routes.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button {
                    viewMode = .list
                } label: {
                    Label("Switch to List View", systemImage: "list.bullet")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Color.white, in: Capsule())
                        .foregroundStyle(.black)
                }
            }
            .padding(28)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            viewMode = .list
        }
    }

    private func centerOnUserIfNeeded() {
        guard !didCenterOnUser,
              let coord = tracker.recordedLocations.last?.coordinate else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: coord,
            latitudinalMeters: homeZoomMeters,
            longitudinalMeters: homeZoomMeters
        ))
        didCenterOnUser = true
    }

    // MARK: - Clustering

    private var clusters: [RouteCluster] {
        clusterRoutes(routes, withinMeters: clusterThresholdMeters)
    }

    // MARK: - List mode adaptive colors

    private var isLight: Bool { colorScheme == .light }

    // #dbeafe light ↔ #1e3a8a dark
    private var iconCircleFill: Color {
        isLight ? Color(red: 0.859, green: 0.914, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541)
    }
    // #2563eb light ↔ #60a5fa dark
    private var iconForeground: Color {
        isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980)
    }
    // #0f172a ink light ↔ white dark
    private var rowNameColor: Color {
        isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white
    }
    // #9fb0d4 muted slate light ↔ #c2cde4 light slate dark
    private var rowCaptionColor: Color {
        isLight ? Color(red: 0.624, green: 0.690, blue: 0.831) : Color(red: 0.761, green: 0.804, blue: 0.894)
    }
    // #c2cde4 light ↔ #9fb0d4 dark
    private var chevronColor: Color {
        isLight ? Color(red: 0.761, green: 0.804, blue: 0.894) : Color(red: 0.624, green: 0.690, blue: 0.831)
    }

    // MARK: - List mode

    private var listHome: some View {
        HomeTabLayout(
            scrollTitle: "Closest Routes",
            scrollItems: suggestedScrollRoutes,
            listTitle: "All Routes",
            listItems: routesForLayout
        ) { route in
            let dist = userCoordinate.flatMap { user in
                route.startCoordinate.map { $0.distance(to: user) }
            }
            RouteCardView(route: route, distanceAway: dist)
                .frame(width: 220)
                .contentShape(Rectangle())
                .onTapGesture { peekRoute = route }
        } listRow: { route in
            routeListRow(route: route)
        }
    }

    private var routesForLayout: [Route] {
        guard let user = userCoordinate else { return routes }
        return routes.sorted {
            ($0.startCoordinate?.distance(to: user) ?? .infinity) <
            ($1.startCoordinate?.distance(to: user) ?? .infinity)
        }
    }

    private var suggestedScrollRoutes: [Route] {
        Array(routesForLayout.prefix(5))
    }

    private func routeListRow(route: Route) -> some View {
        Button { peekRoute = route } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(iconCircleFill)
                        .frame(width: 36, height: 36)
                    Text("\(route.sessions.count)")
                        .font(.headline.bold())
                        .foregroundStyle(iconForeground)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.name)
                        .font(.headline)
                        .foregroundStyle(rowNameColor)
                    HStack(spacing: 4) {
                        Text(Formatters.distance(route.distanceMeters))
                        Text("·")
                        Text("\(route.sessions.count) run\(route.sessions.count == 1 ? "" : "s")")
                    }
                    .font(.caption)
                    .foregroundStyle(rowCaptionColor)
                }
                Spacer()
                if route.isFavorite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.922, green: 0.302, blue: 0.400))
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(chevronColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        tracker.recordedLocations.last?.coordinate
    }
}

// MARK: - Clustering helper

/// Single-link connected-components clustering of routes whose start coordinates
/// fall within `meters` of each other (transitively).
func clusterRoutes(_ routes: [Route], withinMeters meters: CLLocationDistance) -> [RouteCluster] {
    let coords: [(route: Route, coord: CLLocationCoordinate2D)] = routes.compactMap { r in
        guard let c = r.startCoordinate else { return nil }
        return (r, c)
    }
    var clusters: [RouteCluster] = []
    var visited = Set<Int>()  // indices into `coords`

    for i in coords.indices {
        if visited.contains(i) { continue }
        var members: [Route] = []
        var queue: [Int] = [i]
        while let idx = queue.popLast() {
            if visited.contains(idx) { continue }
            visited.insert(idx)
            members.append(coords[idx].route)
            for j in coords.indices where !visited.contains(j) {
                if coords[idx].coord.distance(to: coords[j].coord) <= meters {
                    queue.append(j)
                }
            }
        }
        let lats = members.compactMap { $0.startCoordinate?.latitude }
        let lons = members.compactMap { $0.startCoordinate?.longitude }
        let centroid = CLLocationCoordinate2D(
            latitude: lats.reduce(0, +) / Double(lats.count),
            longitude: lons.reduce(0, +) / Double(lons.count)
        )
        clusters.append(RouteCluster(routes: members, coordinate: centroid))
    }
    return clusters
}

// MARK: - Cluster sheet

struct ClusterSheet: View {
    let routes: [Route]
    let onSelect: (Route) -> Void

    var body: some View {
        NavigationStack {
            List(routes) { route in
                Button {
                    onSelect(route)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(truncatedRouteName(route.name))
                                .font(.headline)
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Label(Formatters.distance(route.distanceMeters), systemImage: "ruler")
                                Label("\(route.sessions.count) sessions", systemImage: "figure.run")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("\(routes.count) Routes Here")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Route card (list mode scroll)

struct RouteCardView: View {
    let route: Route
    var distanceAway: Double? = nil

    private var routeCoordinates: [CLLocationCoordinate2D] {
        route.sortedDefinitionPoints.map(\.coordinate)
    }

    private var previewPosition: MapCameraPosition {
        guard !routeCoordinates.isEmpty else { return .automatic }
        let lats = routeCoordinates.map(\.latitude)
        let lons = routeCoordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(
            latitude: (lats.min()! + lats.max()!) / 2,
            longitude: (lons.min()! + lons.max()!) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 0.002),
            longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 0.002)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        VStack(spacing: 0) {
            Map(initialPosition: previewPosition) {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(.blue, lineWidth: 2.5)
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls { }
            .disabled(true)
            .allowsHitTesting(false)
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 2) {
                Text(route.name)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let dist = distanceAway {
                    Text("\(Formatters.distance(dist)) away")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
    }
}
