import SwiftUI
import SwiftData
import CoreLocation
import MapKit

// MARK: - Helpers

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

enum RouteSort: String, CaseIterable, Identifiable {
    case distanceFromYou = "Distance From You"
    case mostFrequent = "Most Frequently Used"
    case lapDistance = "Lap Distance"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .distanceFromYou: return "location.fill"
        case .mostFrequent: return "flame.fill"
        case .lapDistance: return "ruler"
        }
    }
}

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
private let routeNameRowCharLimit = 16

private func truncatedRouteName(_ name: String, limit: Int = routeNameRowCharLimit) -> String {
    name.count <= limit ? name : String(name.prefix(limit)) + "…"
}

// MARK: - ContentView (TabView shell)

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SurgeSession.createdAt, order: .reverse) private var allSurgeSessions: [SurgeSession]

    @State private var selectedTab: Int = 0
    @State private var lastValidTab: Int = 0
    @State private var sessionsPath = NavigationPath()

    // Tab tags. The blue bolt sits dead-center.
    private let routesTab = 0
    private let planTab = 1
    private let surgeTab = 2
    private let sessionsTab = 3
    private let settingsTab = 4

    /// SF Symbol rendered with an explicit blue tint that the tab bar won't re-tint
    /// to grey when the item is unselected. UIImage's `.alwaysOriginal` rendering
    /// mode is what bypasses the system's automatic tint coloring.
    private static let surgeTabIcon: UIImage = {
        UIImage(systemName: "bolt.fill")?
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal) ?? UIImage()
    }()

    /// True when there is an unexpired surge session — the next started workout will attach to it.
    private var hasCurrentSurge: Bool {
        allSurgeSessions.contains { $0.isCurrent }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            RoutesHomeView()
                .tabItem {
                    Label("Routes", systemImage: "figure.run")
                }
                .tag(routesTab)

            PlansHomeView()
                .tabItem {
                    Label("Plan", systemImage: "list.clipboard")
                }
                .tag(planTab)

            // Action-only middle tab. "Surging" while there's an active surge session
            // (taps jump to its detail); "Surge" otherwise (taps pop to Routes).
            Color.clear
                .tabItem {
                    Label {
                        Text(hasCurrentSurge ? "Surging" : "Surge")
                    } icon: {
                        Image(uiImage: Self.surgeTabIcon)
                    }
                }
                .tag(surgeTab)

            SessionsHomeView(path: $sessionsPath)
                .tabItem {
                    Label("Sessions", systemImage: "calendar")
                }
                .tag(sessionsTab)

            SettingsHomeView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(settingsTab)
        }
        .onChange(of: selectedTab) { _, new in
            if new == surgeTab {
                handleSurgeTap()
            } else {
                lastValidTab = new
            }
        }
        .environment(\.startPlan, startPlanAction)
    }

    // MARK: - Surge tab CTA

    private func handleSurgeTap() {
        if let current = SurgeSession.current(in: modelContext) {
            jumpToSurgeDetail(current)
        } else {
            // No active workout — bounce the user to Routes so they can pick one.
            selectedTab = routesTab
            lastValidTab = routesTab
        }
    }

    // MARK: - Plan start

    /// Closure injected via `\.startPlan` environment so `PlanDetailView` can kick off
    /// a workout without knowing about the tab structure.
    private var startPlanAction: (Plan) -> Void {
        { plan in
            let surge: SurgeSession
            if let current = SurgeSession.current(in: modelContext) {
                // Attach this plan to the current surge session if it has none yet.
                if current.plan == nil {
                    current.plan = plan
                    current.name = plan.name
                }
                surge = current
            } else {
                let now = Date()
                let new = SurgeSession(
                    name: plan.name,
                    date: Calendar.current.startOfDay(for: now),
                    createdAt: now
                )
                new.plan = plan
                modelContext.insert(new)
                surge = new
            }
            jumpToSurgeDetail(surge)
        }
    }

    private func jumpToSurgeDetail(_ surge: SurgeSession) {
        var newPath = NavigationPath()
        newPath.append(surge)
        sessionsPath = newPath
        selectedTab = sessionsTab
        lastValidTab = sessionsTab
    }
}

// MARK: - Environment value for "start this plan"

private struct StartPlanKey: EnvironmentKey {
    static let defaultValue: ((Plan) -> Void)? = nil
}

extension EnvironmentValues {
    var startPlan: ((Plan) -> Void)? {
        get { self[StartPlanKey.self] }
        set { self[StartPlanKey.self] = newValue }
    }
}

// MARK: - Routes tab

struct RoutesHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Route.createdAt, order: .reverse) private var routes: [Route]

    @State private var showingCreateRoute = false

    @State private var viewMode: HomeViewMode = .map
    @State private var sort: RouteSort = .distanceFromYou
    @State private var tracker = LocationTracker()
    @State private var cameraPosition: MapCameraPosition = .region(Self.defaultRegion)
    @State private var didCenterOnUser = false

    // Peek sheet + post-dismiss navigation
    @State private var peekRoute: Route?
    @State private var clusterPeek: RouteClusterSelection?
    @State private var pendingEdit: Route?
    @State private var pendingPeek: Route?
    @State private var editingRoute: Route?
    @State private var path = NavigationPath()

    // "Go from map" flow — peek's Go button skips the detail view and jumps
    // straight to the surge-session picker, then into SessionRecordingView.
    @State private var goRoute: Route?
    @State private var goSurge: SurgeSession?

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
            .sheet(item: $peekRoute, onDismiss: handlePeekDismiss) { route in
                RoutePeekSheet(
                    route: route,
                    onUse: {
                        goRoute = route
                        peekRoute = nil
                    },
                    onEdit: {
                        pendingEdit = route
                        peekRoute = nil
                    }
                )
            }
            .navigationDestination(item: $goSurge) { surge in
                if let route = goRoute {
                    SessionRecordingView(route: route, surgeSession: surge)
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

    private func handlePeekDismiss() {
        if goRoute != nil {
            // "Go" was pressed — auto-attach to the current surge session (or create one)
            // and push the recording view directly.
            goSurge = SurgeSession.currentOrNew(in: modelContext)
        } else if let route = pendingEdit {
            editingRoute = route
            pendingEdit = nil
        }
    }

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
        // Drop the one-shot flag so centerOnUserIfNeeded() runs again
        // when the next location arrives, snapping back to the 3 km zoom.
        didCenterOnUser = false
        tracker.requestSingleLocation()
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Routes Yet", systemImage: "figure.run")
        } description: {
            Text("Create your first route with the blue + button above. Walk or run a loop once so the app learns its shape.")
        }
    }

    // MARK: - Map mode

    private var mapHome: some View {
        ZStack {
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

    // MARK: - List mode

    private var listHome: some View {
        let colors = badgeColors()
        return VStack(spacing: 0) {
            sortHeader
            List {
                ForEach(Array(sortedRoutes.enumerated()), id: \.element.id) { idx, route in
                    Button {
                        goRoute = route
                        goSurge = SurgeSession.currentOrNew(in: modelContext)
                    } label: {
                        routeRow(route, color: colors[idx])
                    }
                    .buttonStyle(.plain)
                }
                .onDelete(perform: deleteSortedRoutes)
            }
        }
    }

    private var sortHeader: some View {
        HStack {
            Menu {
                Picker("Sort", selection: $sort) {
                    ForEach(RouteSort.allCases) { option in
                        Label(option.rawValue, systemImage: option.icon).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sorted by:")
                        .foregroundStyle(.secondary)
                    Text(sort.rawValue)
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                }
                .font(.callout)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: Capsule())
                .foregroundStyle(.primary)
            }
            if sort == .distanceFromYou && userCoordinate == nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help("Current location unavailable — showing default order.")
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private var sortedRoutes: [Route] {
        switch sort {
        case .distanceFromYou:
            guard let user = userCoordinate else { return routes }
            return routes.sorted { a, b in
                let da = a.startCoordinate?.distance(to: user) ?? .infinity
                let db = b.startCoordinate?.distance(to: user) ?? .infinity
                return da < db
            }
        case .mostFrequent:
            return routes.sorted { lhs, rhs in
                if lhs.sessions.count == rhs.sessions.count {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.sessions.count > rhs.sessions.count
            }
        case .lapDistance:
            return routes.sorted { $0.distanceMeters < $1.distanceMeters }
        }
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        tracker.recordedLocations.last?.coordinate
    }

    private func routeRow(_ route: Route, color: Color) -> some View {
        HStack(spacing: 12) {
            sortBadge(for: route, color: color)
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
        }
    }

    private func sortBadge(for route: Route, color: Color) -> some View {
        let (label, _) = badgeValue(for: route)
        return Text(label)
            .font(.system(.callout, design: .rounded, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 64, height: 48)
            .background(color, in: RoundedRectangle(cornerRadius: 10))
    }

    private func badgeValue(for route: Route) -> (label: String, isUnavailable: Bool) {
        switch sort {
        case .distanceFromYou:
            if let user = userCoordinate, let start = route.startCoordinate {
                return (Formatters.distance(start.distance(to: user)), false)
            }
            return ("—", true)
        case .mostFrequent:
            return ("\(route.sessions.count)x", false)
        case .lapDistance:
            return (Formatters.distance(route.distanceMeters), false)
        }
    }

    /// Numeric value used to detect ties between adjacent rows when assigning colors.
    /// Routes whose value matches the previous row keep that row's color.
    private func sortValue(for route: Route) -> Double {
        switch sort {
        case .distanceFromYou:
            guard let user = userCoordinate, let start = route.startCoordinate else { return .infinity }
            return start.distance(to: user)
        case .mostFrequent:
            return Double(route.sessions.count)
        case .lapDistance:
            return route.distanceMeters
        }
    }

    /// One color per row, in display order. Adjacent rows with equal `sortValue` share
    /// the color of the earlier row, so e.g. three routes all tied at "1 session"
    /// render as three green badges, not green/amber/red.
    private func badgeColors() -> [Color] {
        let routes = sortedRoutes
        guard !routes.isEmpty else { return [] }
        var result: [Color] = []
        var lastValue: Double? = nil
        var lastColor: Color? = nil
        for (i, route) in routes.enumerated() {
            let (_, isUnavailable) = badgeValue(for: route)
            if isUnavailable {
                result.append(Color(.systemGray3))
                lastValue = nil
                lastColor = nil
                continue
            }
            let value = sortValue(for: route)
            if let lv = lastValue, value == lv, let lc = lastColor {
                result.append(lc)
            } else {
                let color = Self.gradientColor(rank: i, total: routes.count)
                result.append(color)
                lastValue = value
                lastColor = color
            }
        }
        return result
    }

    /// Maps `rank` in [0, total-1] to a smooth green → amber → red color stop.
    /// Single-item lists are fully green.
    static func gradientColor(rank: Int, total: Int) -> Color {
        guard total > 1 else { return Color(red: 0.20, green: 0.70, blue: 0.30) }
        let t = Double(rank) / Double(total - 1)
        return interpolate(at: t)
    }

    private static func interpolate(at t: Double) -> Color {
        // Three-stop gradient: green @ 0, amber @ 0.5, red @ 1.
        let stops: [(Double, Double, Double, Double)] = [
            (0.0, 0.20, 0.70, 0.30),
            (0.5, 0.95, 0.70, 0.10),
            (1.0, 0.85, 0.20, 0.20),
        ]
        let clamped = max(0, min(1, t))
        var lower = stops[0]
        var upper = stops[1]
        for i in 1..<stops.count where clamped <= stops[i].0 {
            lower = stops[i - 1]
            upper = stops[i]
            break
        }
        let span = upper.0 - lower.0
        let local = span > 0 ? (clamped - lower.0) / span : 0
        return Color(
            red: lower.1 + (upper.1 - lower.1) * local,
            green: lower.2 + (upper.2 - lower.2) * local,
            blue: lower.3 + (upper.3 - lower.3) * local
        )
    }

    private func deleteSortedRoutes(_ offsets: IndexSet) {
        let display = sortedRoutes
        let toDelete = offsets.map { display[$0] }
        for route in toDelete {
            modelContext.delete(route)
        }
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

// MARK: - Sessions tab (calendar + surge sessions)

struct SessionsHomeView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            CalendarHomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SurgeSession.self) { surge in
                    SurgeSessionDetailView(surgeSession: surge)
                }
        }
    }
}

struct CalendarHomeView: View {
    @Query(sort: \SurgeSession.date, order: .reverse) private var surgeSessions: [SurgeSession]
    @State private var selectedDate: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            CalendarMonthView(selectedDate: $selectedDate, activeDates: activeDates)
                .padding(.horizontal)
                .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            if sessionsOnSelectedDate.isEmpty {
                emptyDayView
            } else {
                List {
                    ForEach(sessionsOnSelectedDate.sorted { $0.createdAt < $1.createdAt }) { surge in
                        NavigationLink(value: surge) {
                            surgeRow(surge)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyDayView: some View {
        VStack {
            Spacer()
            Text(emojiForSelectedDate)
                .font(.system(size: 96))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Stable per-day emoji so each rest day keeps its character.
    private var emojiForSelectedDate: String {
        let day = Int(Calendar.current.startOfDay(for: selectedDate).timeIntervalSince1970) / 86_400
        let idx = abs(day) % Self.restDayEmojis.count
        return Self.restDayEmojis[idx]
    }

    private static let restDayEmojis: [String] = [
        "🦒", "🌮", "🦄", "🍕", "🐙", "🥑", "🦝", "🦦", "🦔", "🐧",
        "🥨", "🦥", "🍩", "🌭", "🦩", "🐌", "🦨", "🐢", "🦛", "🐦",
        "🍔", "🥯", "🥞", "🌯", "🥗", "🐳", "🐋", "🌈", "🛸", "🦕",
        "🦖", "🍄", "🌵", "🦂", "🍉", "🐡", "🦞", "🪅", "🎲", "🥟",
        "🦨", "🪐", "🛼", "🎯", "🧸", "🪼", "🦭", "🐲", "🍙", "🥒",
    ]

    private var activeDates: Set<Date> {
        Set(surgeSessions.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var sessionsOnSelectedDate: [SurgeSession] {
        surgeSessions.filter {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    private func surgeRow(_ surge: SurgeSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(surge.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.headline)
                .monospacedDigit()
            HStack(spacing: 10) {
                Text("\(surge.sessions.count) session\(surge.sessions.count == 1 ? "" : "s")")
                if let dur = surge.totalDurationSeconds {
                    Text("·")
                    Text(Formatters.duration(dur))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Custom month-grid calendar with active-day dots

struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    let activeDates: Set<Date>

    @State private var displayedMonth: Date

    private let calendar: Calendar = .current

    init(selectedDate: Binding<Date>, activeDates: Set<Date>) {
        self._selectedDate = selectedDate
        self.activeDates = activeDates
        let start = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        ) ?? selectedDate.wrappedValue
        self._displayedMonth = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 10) {
            monthHeader
            weekdayHeader
            daysGrid
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title3.bold())
            Spacer()
            Button {
                changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            Button {
                changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.current
        let symbols = formatter.veryShortWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        let first = calendar.firstWeekday - 1
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var daysGrid: some View {
        let cells = monthDayCells()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let hasSession = activeDates.contains(calendar.startOfDay(for: date))
        let dayNumber = calendar.component(.day, from: date)

        return VStack(spacing: 3) {
            Text("\(dayNumber)")
                .font(.callout)
                .fontWeight(isSelected || isToday ? .semibold : .regular)
                .foregroundStyle(numberForeground(isSelected: isSelected, isToday: isToday))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : .clear)
                )
            Circle()
                .fill(hasSession ? Color.green : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = date
        }
    }

    private func numberForeground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    private func monthDayCells() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        let firstOfMonth = interval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 0..<daysInMonth {
            if let d = calendar.date(byAdding: .day, value: day, to: firstOfMonth) {
                cells.append(d)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Route.self, inMemory: true)
}
