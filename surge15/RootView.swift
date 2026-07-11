import SwiftUI
import SwiftData

// MARK: - ContentView (TabView shell)

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SurgeSession.createdAt, order: .reverse) private var allSurgeSessions: [SurgeSession]

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("onboardingPhase") private var onboardingPhase: Int = 0

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
        ZStack {
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
            if !hasSeenOnboarding && onboardingPhase == 1 && new != routesTab {
                selectedTab = routesTab
                return
            }
            if !hasSeenOnboarding && onboardingPhase == 3 && new != planTab {
                selectedTab = planTab
                return
            }
            if new == surgeTab {
                handleSurgeTap()
            } else {
                lastValidTab = new
            }
        }
        .environment(\.startPlan, startPlanAction)

        if !hasSeenOnboarding && onboardingPhase == 0 {
            OnboardingIntroView()
                .transition(.opacity)
        }

        if !hasSeenOnboarding && onboardingPhase == 5 {
            surgeTabOnboardingOverlay
                .transition(.opacity)
        }
        } // end ZStack
        .animation(.easeOut(duration: 0.25), value: !hasSeenOnboarding && onboardingPhase == 0)
        .animation(.easeOut(duration: 0.25), value: !hasSeenOnboarding && onboardingPhase == 5)
        .onChange(of: onboardingPhase) { _, phase in
            if phase == 1 {
                selectedTab = routesTab
                lastValidTab = routesTab
            }
            if phase == 3 {
                selectedTab = planTab
                lastValidTab = planTab
            }
            if phase == 5 {
                selectedTab = planTab
                lastValidTab = planTab
            }
        }
    }

    // MARK: - Onboarding overlay (phase 5)

    private var surgeTabOnboardingOverlay: some View {
        VStack(spacing: 0) {
            Spacer()
            OnboardingCallout(
                title: "You Finished The Tutorial!",
                message: "Head to the Routes tab and record your first loop — keep it short, walk or run it once, and you're ready to surge.",
                gotItAction: {
                    hasSeenOnboarding = true
                    selectedTab = routesTab
                    lastValidTab = routesTab
                }
            )
            .padding(.horizontal, 24)
            // Downward arrow centered on screen — points to the bolt (middle tab)
            DownwardTriangle()
                .fill(Color(onboardingHex: "1e3a8a"))
                .frame(width: 20, height: 11)
                .padding(.top, 0)
            Spacer().frame(height: 90)
        }
    }

    private struct DownwardTriangle: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                p.closeSubpath()
            }
        }
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
    private var startPlanAction: (Plan, Route?) -> Void {
        { plan, route in
            let surge: SurgeSession
            if let current = SurgeSession.current(in: modelContext) {
                if current.plan == nil {
                    current.plan = plan
                    current.name = plan.name
                }
                if current.route == nil, let route {
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
    static let defaultValue: ((Plan, Route?) -> Void)? = nil
}

extension EnvironmentValues {
    var startPlan: ((Plan, Route?) -> Void)? {
        get { self[StartPlanKey.self] }
        set { self[StartPlanKey.self] = newValue }
    }
}

#Preview {
    RootView()
        .modelContainer(for: Route.self, inMemory: true)
}
