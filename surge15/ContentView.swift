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
    @State private var showingSurgeDetail = false
    @State private var showingSurgeIntent = false

    // Tab tags. The blue bolt sits dead-center.
    private let routesTab = 0
    private let planTab = 1
    private let surgeTab = 2
    private let sessionsTab = 3
    private let settingsTab = 4

    /// SF Symbol with a fixed blue tint (bypasses the tab bar's automatic re-tinting).
    private static let surgeTabIcon: UIImage = {
        UIImage(systemName: "bolt.fill")?
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal) ?? UIImage()
    }()

    /// Same icon but red — shown while a surge session is active.
    private static let surgingTabIcon: UIImage = {
        UIImage(systemName: "bolt.fill")?
            .withTintColor(.systemRed, renderingMode: .alwaysOriginal) ?? UIImage()
    }()

    /// True when there is an unexpired surge session.
    private var hasCurrentSurge: Bool {
        allSurgeSessions.contains { $0.isCurrent }
    }

    /// The active surge session, if one exists.
    private var currentSurgeSession: SurgeSession? {
        allSurgeSessions.first { $0.isCurrent }
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
                    Label("Plans", systemImage: "list.clipboard")
                }
                .tag(planTab)

            // Action-only middle tab — always redirects, never holds content.
            Color.clear
                .tabItem {
                    Label {
                        Text(hasCurrentSurge ? "Surging" : "Surge")
                    } icon: {
                        Image(uiImage: hasCurrentSurge ? Self.surgingTabIcon : Self.surgeTabIcon)
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
        .tint(hasCurrentSurge ? .red : .accentColor)
        .toolbarBackground(hasCurrentSurge ? Color.red.opacity(0.12) : Color(.systemBackground).opacity(0), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .sheet(isPresented: $showingSurgeDetail) {
            if let surge = currentSurgeSession {
                NavigationStack {
                    SurgeSessionDetailView(surgeSession: surge)
                }
            }
        }
        .sheet(isPresented: $showingSurgeIntent) {
            SurgeIntentView(
                onRunRoute: {
                    showingSurgeIntent = false
                    selectedTab = routesTab
                    lastValidTab = routesTab
                },
                onExecutePlan: {
                    showingSurgeIntent = false
                    selectedTab = planTab
                    lastValidTab = planTab
                }
            )
        }
        .onChange(of: hasCurrentSurge) { _, isActive in
            if !isActive { showingSurgeDetail = false }
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
        if hasCurrentSurge {
            showingSurgeDetail = true
        } else {
            showingSurgeIntent = true
        }
        selectedTab = lastValidTab
    }

    // MARK: - Plan start

    /// Closure injected via `\.startPlan` environment so `PlanDetailView` can kick off
    /// a workout without knowing about the tab structure.
    private var startPlanAction: (Plan, Route) -> Void {
        { plan, route in
            let surge: SurgeSession
            if let current = SurgeSession.current(in: modelContext) {
                if current.plan == nil {
                    current.plan = plan
                    current.name = plan.name
                }
                if current.route == nil {
                    current.route = route
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
                new.route = route
                modelContext.insert(new)
                surge = new
            }
            jumpToSurgeDetail(surge)
        }
    }

    private func jumpToSurgeDetail(_ surge: SurgeSession) {
        if surge.isCurrent {
            showingSurgeDetail = true
        } else {
            var newPath = NavigationPath()
            newPath.append(surge)
            sessionsPath = newPath
            selectedTab = sessionsTab
            lastValidTab = sessionsTab
        }
    }
}

// MARK: - Environment value for "start this plan"

private struct StartPlanKey: EnvironmentKey {
    static let defaultValue: ((Plan, Route) -> Void)? = nil
}

extension EnvironmentValues {
    var startPlan: ((Plan, Route) -> Void)? {
        get { self[StartPlanKey.self] }
        set { self[StartPlanKey.self] = newValue }
    }
}

// MARK: - Routes tab

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
    @State private var pendingEdit: Route?
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

    private func handlePeekDismiss() {
        if goRoute != nil {
            navigatingToRecording = true
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
                suggestionDismissed = true
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

    // #f5f8fd light ↔ #070a18 deepest navy dark
    private var pageBackground: Color {
        isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094)
    }
    // white light ↔ #0e1430 deep navy dark
    private var listContainerBg: Color {
        isLight ? .white : Color(red: 0.055, green: 0.078, blue: 0.188)
    }
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
    // #2563eb light ↔ #60a5fa dark
    private var sectionLabelColor: Color {
        isLight ? Color(red: 0.145, green: 0.388, blue: 0.922) : Color(red: 0.376, green: 0.647, blue: 0.980)
    }
    // #bfdbfe light ↔ #1e3a8a dark
    private var dividerColor: Color {
        isLight ? Color(red: 0.749, green: 0.859, blue: 0.996) : Color(red: 0.118, green: 0.227, blue: 0.541)
    }

    // MARK: - List mode

    private var listHome: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                let suggested = suggestedRoutes
                let favorites = routes.filter { $0.isFavorite }

                if !suggested.isEmpty {
                    routeShelf(title: "Suggested Routes", routes: suggested)
                }

                if !favorites.isEmpty {
                    routeShelf(title: "Favorites", routes: favorites)
                }

                if !routes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        listSectionHeader("All Routes")
                            .padding(.horizontal)
                        VStack(spacing: 0) {
                            ForEach(Array(allRoutesSorted.enumerated()), id: \.element.id) { idx, route in
                                routeListRow(route: route, isLast: idx == routes.count - 1)
                            }
                        }
                        .background(listContainerBg, in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.top, 16)
        }
        .background(pageBackground.ignoresSafeArea())
    }

    private var suggestedRoutes: [Route] {
        guard let user = userCoordinate else {
            return Array(routes.sorted { $0.sessions.count > $1.sessions.count }.prefix(2))
        }
        let byDistance = routes.sorted {
            ($0.startCoordinate?.distance(to: user) ?? .infinity) <
            ($1.startCoordinate?.distance(to: user) ?? .infinity)
        }
        var suggestions: [Route] = []
        for route in byDistance {
            if suggestions.count == 2 { break }
            var merged = false
            for i in suggestions.indices {
                guard let c1 = route.startCoordinate,
                      let c2 = suggestions[i].startCoordinate else { continue }
                if c1.distance(to: c2) <= 50 {
                    if route.sessions.count > suggestions[i].sessions.count {
                        suggestions[i] = route
                    }
                    merged = true
                    break
                }
            }
            if !merged { suggestions.append(route) }
        }
        return suggestions
    }

    private var allRoutesSorted: [Route] {
        guard let user = userCoordinate else { return routes }
        return routes.sorted {
            ($0.startCoordinate?.distance(to: user) ?? .infinity) <
            ($1.startCoordinate?.distance(to: user) ?? .infinity)
        }
    }

    private func routeShelf(title: String, routes: [Route]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            listSectionHeader(title)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(routes) { route in
                        routeCardButton(route)
                            .frame(width: 130)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        }
    }

    private func routeCardButton(_ route: Route) -> some View {
        Button { peekRoute = route } label: { RouteCardView(route: route) }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    route.isFavorite.toggle()
                } label: {
                    Label(route.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                          systemImage: route.isFavorite ? "heart.slash" : "heart")
                }
                Button { editingRoute = route } label: {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive) { deletingRoute = route } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func routeListRow(route: Route, isLast: Bool) -> some View {
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
        .contextMenu {
            Button { route.isFavorite.toggle() } label: {
                Label(route.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                      systemImage: route.isFavorite ? "heart.slash" : "heart")
            }
            Button { editingRoute = route } label: { Label("Edit", systemImage: "pencil") }
            Button(role: .destructive) { deletingRoute = route } label: { Label("Delete", systemImage: "trash") }
        }
        .overlay(alignment: .bottom) {
            if !isLast {
                dividerColor
                    .frame(height: 0.5)
                    .padding(.leading, 64)
            }
        }
    }

    private func listSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(sectionLabelColor)
            .textCase(.uppercase)
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
    private enum ViewMode { case calendar, analytics }

    @Query(sort: \SurgeSession.date, order: .reverse) private var surgeSessions: [SurgeSession]
    @State private var selectedDate: Date = Date()
    @State private var viewMode: ViewMode = .calendar

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $viewMode) {
                Text("Calendar").tag(ViewMode.calendar)
                Text("Analytics").tag(ViewMode.analytics)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if viewMode == .calendar {
                CalendarMonthView(selectedDate: $selectedDate, activeDates: activeDates)
                    .padding(.horizontal)

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
            } else {
                AnalyticsView()
            }
        }
    }

    private var emptyDayView: some View {
        VStack {
            Spacer()
            Text(quoteForSelectedDate)
                .font(.title3.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var isFuture: Bool {
        Calendar.current.startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date())
    }

    /// Today with no sessions → motivating nudge. Future day → playful forward-look. Past empty day → roast.
    private var quoteForSelectedDate: String {
        let day = Int(Calendar.current.startOfDay(for: selectedDate).timeIntervalSince1970) / 86_400
        if isToday {
            return Self.todayNudgeQuotes[abs(day) % Self.todayNudgeQuotes.count]
        }
        if isFuture {
            return Self.futureDayQuotes[abs(day) % Self.futureDayQuotes.count]
        }
        return Self.restDayQuotes[abs(day) % Self.restDayQuotes.count]
    }

    private static let futureDayQuotes: [String] = [
        "Woah, you're already planning your workout for this day.",
        "Love the commitment. This day isn't even here yet.",
        "Scouting out future suffering. Respect.",
        "The future you is already lacing up. Probably.",
        "Bold of you to assume you'll want to on this day.",
        "Pencil it in. Then actually show up.",
        "A blank slate. Infinite potential. No excuses yet.",
        "Future you will either thank you or blame you for this.",
        "This day is wide open. Nice.",
        "Pre-regretting skipping this one. Smart.",
        "You're thinking about the future. The future is thinking back.",
        "All that free space just waiting for a surge.",
        "Looking ahead. We love to see it.",
    ]

    private static let todayNudgeQuotes: [String] = [
        "How about a quick run? Or 2? Or 3? Or 4?",
        "The day isn't over yet. Just saying.",
        "One lap. That's all. One tiny lap.",
        "Future you is rooting for present you. Loudly.",
        "What if you laced up right now? Wild thought.",
        "You've done harder things before breakfast.",
        "The route isn't going to run itself. Yet.",
        "A ten-minute run beats a zero-minute run every time.",
        "Go outside. Touch grass. Then run past it.",
        "You could start right now and be done before this sinks in.",
        "Not too late. Never too late. Especially not right now.",
        "One session. One decision. Let's go.",
        "Your shoes are literally right there.",
        "The only bad workout is the one that didn't happen today.",
        "You didn't come this far to skip today.",
        "The run is short. The feeling after is long.",
        "Champion energy available. Currently unclaimed.",
        "Still today. Still time. Still you.",
    ]

    private static let restDayQuotes: [String] = [
        "The couch called. You answered every time.",
        "A+ for showing up. F for moving.",
        "Rest day, or just... day?",
        "Your sneakers are collecting dust and personality.",
        "Somewhere, a treadmill is crying.",
        "The only reps today were lifting the remote.",
        "You trained hard. At doing nothing.",
        "Officially a professional rester.",
        "The gym misses you. Probably.",
        "Netflix: 1. Workout: 0.",
        "Today's workout sponsored by: the couch.",
        "You looked outside and said nope. Valid.",
        "Invisible reps. They totally count.",
        "Strong choice to do absolutely nothing.",
        "Your body is a temple. Closed today.",
        "The weights lifted themselves. You weren't there to see it.",
        "Rest is training too. ...Probably.",
        "Every champion needs a cloud watching day.",
        "You burned calories blinking. That's something.",
        "You rested so hard. Respect.",
        "Officially fueling up for next time.",
        "Today: recovery mode. From what? Unclear.",
        "The road wasn't going anywhere. You matched its energy.",
        "Legs? Never heard of them.",
        "Zero steps taken. One hundred thoughts had.",
        "You thought about working out. That's like half.",
        "The bed was too comfy. A worthy opponent.",
        "Today's pace: glacial.",
        "Warming the bench like a pro.",
        "You did nothing today with incredible commitment.",
        "Peak performance at resting.",
        "The alarm went off. You negotiated. The alarm lost.",
        "Your future self is already judging this. Lovingly.",
        "Saving energy for something important. TBD.",
        "You were in the zone. The comfort zone.",
        "Olympic-level relaxation on display here.",
        "Somewhere, a protein shake went unmade.",
        "You took the scenic route: straight to the sofa.",
        "Today was brought to you by: zero effort.",
        "You thought about lunges. That's enough.",
        "The run will still be there tomorrow. Pinky promise.",
        "Resting face AND resting legs. Synergy.",
        "Even elite athletes have days like this. Probably.",
        "Today: 0 km. Confidence: unchanged.",
        "You looked at your running shoes and said: not today, friend.",
        "A bold day to do absolutely zip.",
        "Recovery is a strategy. You're very strategic.",
        "No sessions logged. Vibe preserved.",
        "You rested like it was your job. Nailed it.",
        "The track was out there. You were in here. Balance.",
        "You gave your muscles a vacation. They send their thanks.",
        "The burpees can wait. They're very patient.",
        "Today's training log: thoughts and prayers.",
        "Technically, breathing is cardio.",
        "You were at full power the whole time. Power to relax.",
        "Your running shoes sat by the door, hopeful.",
        "You took a step back. Literally.",
        "A true rest day: no guilt, no gains, no problem.",
        "The workout planned. The day laughed.",
        "Today's miles: 0. Today's memories: unclear.",
        "The road less traveled was, in fact, not traveled.",
        "Rest hard. Play harder. Workout... eventually.",
        "Today you trained your ability to not train.",
        "A skip day is just a future motivation origin story.",
        "You rested with intention. Very zen.",
        "Legend has it they were going to work out. But first, a nap.",
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
        HStack(alignment: .center, spacing: 16) {
            // Left: start time + total elapsed
            VStack(alignment: .leading, spacing: 3) {
                Text(surge.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text(surge.totalDurationSeconds.map { Formatters.duration($0) } ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 88, alignment: .leading)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 44)

            // Right: one bubble per session in order, or a funny quote if empty
            if surge.sortedSessions.isEmpty {
                let seed = Int(surge.createdAt.timeIntervalSince1970)
                Text(Self.emptySessionQuotes[abs(seed) % Self.emptySessionQuotes.count])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
            } else {
                HStack(spacing: 6) {
                    ForEach(surge.sortedSessions) { session in
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 36, height: 36)
                            Image(systemName: (session.workoutType ?? .run).systemImage)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private static let emptySessionQuotes: [String] = [
        "A+ for showing up. F for moving.",
        "Invisible reps. They totally count.",
        "Rest is training too. ...Probably.",
        "Recovery is a strategy. You're very strategic.",
        "You rested with intention. Very zen.",
        "Technically, breathing is cardio.",
        "Peak performance at resting.",
    ]
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

// MARK: - Surge intent chooser

struct SurgeIntentView: View {
    let onRunRoute: () -> Void
    let onExecutePlan: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Query private var routes: [Route]
    @Query private var plans: [Plan]

    @State private var quote: String = ""

    private static let quotes: [String] = [
        // Original 15
        "I see you. Putting in that work.",
        "The couch called. You didn't answer.",
        "Legs don't know it's leg day. Surprise them.",
        "You showed up. That's already 50% of it.",
        "Your future self is watching. Don't disappoint them.",
        "No one ever regretted a workout. Maybe one person...but who's counting?",
        "Sweat is just your body applauding itself.",
        "You vs. you. You're winning.",
        "The only bad workout is the one that didn't happen.",
        "The route isn't going to run itself.",
        "Your body can. Your brain is just being dramatic.",
        "Let's get this bread. And then burn it off.",
        "Today's discomfort is tomorrow's warm-up.",
        "You're here. The hard part is already done.",
        "Champions train on the days they don't want to.",
        // 50 new ones
        "Pain is temporary. Screenshots of your stats are forever.",
        "Your muscles don't know it's early. Neither does your alarm. Go.",
        "Every kilometre you don't run, someone else is running it. Rude of them.",
        "Plot twist: you feel amazing after.",
        "You drove here. You might as well.",
        "Technically, blinking is cardio. But let's aim higher.",
        "Your heart wants to. Your legs will follow.",
        "You didn't come this far to only come this far.",
        "Somewhere, someone is using your motivation as their excuse not to go. Don't let them win.",
        "This is the part of the movie where you get up.",
        "Outrun your thoughts. There are a lot of them today.",
        "You've survived worse. You can survive a lap or two.",
        "Not all heroes wear capes. Some wear compression socks.",
        "The best time to work out was yesterday. The second best time is right now.",
        "One decision. One direction. One very sore tomorrow.",
        "Your body keeps the score. Make sure the score is good.",
        "Lace up. The route isn't going anywhere, but you should.",
        "You've been thinking about this all day. Now stop thinking.",
        "Discipline is just motivation with a better attendance record.",
        "Run like someone's watching. Because your future self is.",
        "The gym doesn't care about your feelings. But we do. Now go.",
        "You are one workout away from a good mood.",
        "Your legs have been waiting all day for this. They're excited. Trust them.",
        "The only person you need to be better than is last week's you.",
        "Surge. Then brunch. In that order.",
        "Go fast. Go slow. Just go.",
        "Your sneakers have been by the door all day, hopeful.",
        "The route has been patiently waiting. It's time.",
        "New body unlocked. It's on the other side of this workout.",
        "You are legally required to feel good after this. Look it up.",
        "Sometimes the hardest part is opening the app. Done. You win.",
        "Elite mindset. Amateur excuse count: zero.",
        "Later you will say: I'm glad I did that. Trust later you.",
        "You didn't skip. Iconic.",
    ]

    private var isLight: Bool { colorScheme == .light }
    private var pageBackground: Color {
        isLight ? Color(red: 0.961, green: 0.973, blue: 0.992) : Color(red: 0.027, green: 0.039, blue: 0.094)
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("\"\(quote)\"")
                .font(.subheadline.italic())
                .foregroundStyle(isLight ? Color(red: 0.059, green: 0.090, blue: 0.165) : .white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.bottom, 14)

            intentTile(
                title: "Run a Route",
                subtitle: "GPS-tracked laps on your personal loop",
                emptyNudge: "No routes yet — go create one",
                icon: "figure.run",
                count: routes.count,
                countLabel: "route",
                // #1e3a8a → #2563eb  Navy → Primary Blue
                gradient: LinearGradient(
                    colors: [Color(red: 0.118, green: 0.227, blue: 0.541), Color(red: 0.145, green: 0.388, blue: 0.922)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                action: onRunRoute
            )
            .padding(.bottom, 10)
            intentTile(
                title: "Execute a Plan",
                subtitle: "Work through your structured workout",
                emptyNudge: "No plans yet — go create one",
                icon: "bolt.fill",
                count: plans.count,
                countLabel: "plan",
                // #15235a → #60a5fa  Mid Navy → Light Blue
                gradient: LinearGradient(
                    colors: [Color(red: 0.082, green: 0.137, blue: 0.353), Color(red: 0.376, green: 0.647, blue: 0.980)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                action: onExecutePlan
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(320)])
        .presentationBackground(pageBackground)
        .onAppear {
            quote = SurgeIntentView.quotes.randomElement() ?? ""
        }
    }

    private func intentTile(
        title: String,
        subtitle: String,
        emptyNudge: String,
        icon: String,
        count: Int,
        countLabel: String,
        gradient: LinearGradient,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                ZStack(alignment: .bottomLeading) {
                    gradient
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.4)],
                        startPoint: .top, endPoint: .bottom
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Image(systemName: icon)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            if count > 0 {
                                Text("\(count) \(countLabel)\(count == 1 ? "" : "s")")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(.white.opacity(0.2), in: Capsule())
                            } else {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        Spacer()
                        Text(title)
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)

            if count == 0 {
                Button(action: action) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text(emptyNudge)
                        Image(systemName: "arrow.right")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }
}

// Brand-palette navy → blue gradients for route cards
private let routeCardGradients: [LinearGradient] = [
    // #1e3a8a → #2563eb  Navy → Primary Blue
    LinearGradient(colors: [Color(red: 0.118, green: 0.227, blue: 0.541), Color(red: 0.145, green: 0.388, blue: 0.922)], startPoint: .topLeading, endPoint: .bottomTrailing),
    // #15235a → #60a5fa  Mid Navy → Light Blue
    LinearGradient(colors: [Color(red: 0.082, green: 0.137, blue: 0.353), Color(red: 0.376, green: 0.647, blue: 0.980)], startPoint: .topLeading, endPoint: .bottomTrailing),
    // #0e1430 → #1e3a8a  Deep Navy → Navy
    LinearGradient(colors: [Color(red: 0.055, green: 0.078, blue: 0.188), Color(red: 0.118, green: 0.227, blue: 0.541)], startPoint: .topLeading, endPoint: .bottomTrailing),
    // #1e3a8a → #5a8df0  Navy → Softer Blue
    LinearGradient(colors: [Color(red: 0.118, green: 0.227, blue: 0.541), Color(red: 0.353, green: 0.553, blue: 0.941)], startPoint: .topLeading, endPoint: .bottomTrailing),
    // #070a18 → #2563eb  Deepest Navy → Primary Blue
    LinearGradient(colors: [Color(red: 0.027, green: 0.039, blue: 0.094), Color(red: 0.145, green: 0.388, blue: 0.922)], startPoint: .topLeading, endPoint: .bottomTrailing),
    // #15235a → #93c5fd  Mid Navy → Pale Blue
    LinearGradient(colors: [Color(red: 0.082, green: 0.137, blue: 0.353), Color(red: 0.576, green: 0.773, blue: 0.992)], startPoint: .topLeading, endPoint: .bottomTrailing),
]

struct RouteCardView: View {
    let route: Route

    private var gradient: LinearGradient {
        routeCardGradients[abs(route.name.hashValue) % routeCardGradients.count]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.35)],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "figure.run")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if route.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }
                Spacer()
                Text(route.name)
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                HStack(spacing: 6) {
                    Text(Formatters.distance(route.distanceMeters))
                    Text("·")
                    Text("\(route.sessions.count) run\(route.sessions.count == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 118)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Route.self, inMemory: true)
}
