//
//  SessionRecordingView.swift
//  surge15
//
//  Executes one Session on an existing Route.
//  - Start is gated until the user is within 20 m of the route's start point.
//  - User picks how many laps to run before starting (defaults to 1).
//  - A lap auto-completes when cumulative lap distance reaches the route's
//    total segment distance. (No "return within 20 m" check — once you start
//    at the gate, distance is what matters.)
//  - When the cumulative lap distance crosses an interior segment boundary,
//    the user gets a strong haptic buzz + a full-screen TURN AROUND overlay.
//

import SwiftUI
import SwiftData
import CoreLocation
import MapKit
import UIKit

enum SessionMode { case laps, distance }

struct SessionRecordingView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var route: Route

    var initialMode: SessionMode = .laps
    var initialTarget: Double = 1.0

    @State private var tracker = LocationTracker()

    // Session-level
    @State private var startedAt: Date?
    @State private var sessionStartIndex: Int = 0
    @State private var sessionMode: SessionMode = .laps
    @State private var targetLaps: Int = 1
    @State private var targetMeters: Double = 400

    // Per-lap
    @State private var currentLapStartedAt: Date?
    @State private var currentLapStartIndex: Int = 0
    @State private var lapCompletions: [Date] = []

    // Surge session — resolved lazily when the user taps Start, not on view load.
    @State private var surgeSession: SurgeSession?

    // Countdown
    @State private var countdownRemaining: Int = 0
    @State private var isCountingDown = false
    @State private var countdownTask: Task<Void, Never>?

    // UI
    @State private var now = Date()
    @State private var hasSaved = false
    @State private var didAutoStop = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didCenterCamera = false

    // Segment alerts
    @State private var announcedSegmentsInLap: Set<Int> = []
    @State private var turnaroundAlertVisible = false
    @State private var turnaroundAlertDirection: SegmentDirection = .around

    private let startToleranceMeters: CLLocationDistance = 20
    private let maxLaps: Int = 100
    private let lapPresets    = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 20, 25, 50, 100]
    private let meterPresets: [Double] = [1, 5, 10, 20, 40, 50, 75, 100, 125, 150, 200, 250,
                                          300, 350, 400, 450, 500, 550, 600, 650, 700, 750,
                                          800, 850, 900, 950, 1000]

    var body: some View {
        ZStack {
            if hasSaved {
                VStack(spacing: 24) {
                    Spacer()
                    completedBlock
                    Spacer()
                    doneButton
                }
                .padding()
            } else if isGateState {
                gateMapFullScreen
                    .overlay(alignment: .bottom) {
                        VStack(spacing: 8) {
                            authorizationFootnote
                            gateStatusBanner
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    activeBlock
                    Spacer()
                    authorizationFootnote
                }
                .padding()
            }

            if turnaroundAlertVisible {
                turnaroundOverlay
                    .transition(.opacity)
            }

            if isCountingDown {
                countdownOverlay
                    .transition(.opacity)
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                actionToolbarPill
            }
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            tracker.requestAuthorization()
            if !tracker.isRecording { tracker.start() }
            centerCameraOnStartIfNeeded()
            sessionMode = initialMode
            if initialMode == .laps {
                targetLaps = max(1, Int(initialTarget))
            } else {
                targetMeters = max(1, initialTarget)
            }
        }
        .onChange(of: tracker.recordedLocations.count) { _, _ in
            checkSegmentBoundaries()
            evaluateAutoStop()
            centerCameraOnStartIfNeeded()
        }
        .onDisappear {
            countdownTask?.cancel()
            if isSessionActive { saveSession() }
            tracker.stop()
        }
    }

    private var turnaroundOverlay: some View {
        ZStack {
            turnaroundAlertDirection.alertColor.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: turnaroundAlertDirection.alertIcon)
                    .font(.system(size: 140))
                    .foregroundStyle(.white)
                Text(turnaroundAlertDirection.alertTitle)
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private var isGateState: Bool {
        !hasSaved && !isSessionActive
    }

    // MARK: - Derived state

    private var isSessionActive: Bool { startedAt != nil && !hasSaved }

    private var currentLocation: CLLocation? { tracker.recordedLocations.last }

    private var distanceToStart: CLLocationDistance? {
        guard let current = currentLocation?.coordinate,
              let start = route.startCoordinate else { return nil }
        return current.distance(to: start)
    }

    private var isWithinStartTolerance: Bool {
        guard let d = distanceToStart else { return false }
        return d <= startToleranceMeters
    }

    private var gateDistanceColor: Color {
        guard let d = distanceToStart else { return Color.black.opacity(0.7) }
        if d <= startToleranceMeters { return .green }
        if d <= 60 { return .orange }
        return .red
    }

    private struct GuidanceArrow {
        let userCoord: CLLocationCoordinate2D
        let startCoord: CLLocationCoordinate2D
        let arrowCoord: CLLocationCoordinate2D
        /// Bearing in degrees from user → start (0 = north, clockwise).
        let bearing: Double
    }

    /// "Walk this way" cue. Drawn from the user's blue dot to the start flag with a
    /// small arrow ~85% of the way along, pointing at the start. Hidden once the user
    /// is inside the 20 m tolerance (the line is no longer informative).
    private var guidanceArrow: GuidanceArrow? {
        guard let userCoord = currentLocation?.coordinate,
              let start = route.startCoordinate,
              !isWithinStartTolerance else { return nil }

        let f = 0.85
        let arrowCoord = CLLocationCoordinate2D(
            latitude: userCoord.latitude + (start.latitude - userCoord.latitude) * f,
            longitude: userCoord.longitude + (start.longitude - userCoord.longitude) * f
        )

        let dLon = (start.longitude - userCoord.longitude) * .pi / 180
        let lat1 = userCoord.latitude * .pi / 180
        let lat2 = start.latitude * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi

        return GuidanceArrow(userCoord: userCoord, startCoord: start, arrowCoord: arrowCoord, bearing: bearing)
    }

    private var sessionLocations: [CLLocation] {
        guard startedAt != nil else { return [] }
        return Array(tracker.recordedLocations.dropFirst(sessionStartIndex))
    }

    private var sessionDistance: CLLocationDistance {
        Route.totalDistance(coordinates: sessionLocations.map(\.coordinate))
    }

    private var currentLapLocations: [CLLocation] {
        guard startedAt != nil else { return [] }
        return Array(tracker.recordedLocations.dropFirst(currentLapStartIndex))
    }

    private var currentLapDistance: CLLocationDistance {
        Route.totalDistance(coordinates: currentLapLocations.map(\.coordinate))
    }

    private var currentLapElapsed: TimeInterval {
        guard let s = currentLapStartedAt else { return 0 }
        return now.timeIntervalSince(s)
    }

    private var totalElapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return now.timeIntervalSince(startedAt)
    }

    private var completedLapCount: Int { lapCompletions.count }

    private var distanceLeftInLap: CLLocationDistance {
        max(0, route.distanceMeters - currentLapDistance)
    }

    private var liveLapDurations: [TimeInterval] {
        guard let sessionStart = startedAt else { return [] }
        var result: [TimeInterval] = []
        var prev = sessionStart
        for ts in lapCompletions {
            result.append(ts.timeIntervalSince(prev))
            prev = ts
        }
        return result
    }

    // MARK: - Status block (active + completed states)

    @ViewBuilder
    private var statusBlock: some View {
        if hasSaved {
            completedBlock
        } else if isSessionActive {
            activeBlock
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var activeBlock: some View {
        if sessionMode == .laps {
            VStack(spacing: 18) {
                Label("Lap \(completedLapCount + 1) of \(targetLaps)", systemImage: "flag.checkered")
                    .font(.headline)

                VStack(spacing: 4) {
                    Text(Formatters.duration(currentLapElapsed))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("current lap time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 32) {
                    statCell(value: Formatters.distance(distanceLeftInLap), label: "left in lap")
                    statCell(value: Formatters.duration(totalElapsed), label: "total time")
                }

                if !liveLapDurations.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Completed laps")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 10) {
                            ForEach(Array(liveLapDurations.enumerated()), id: \.offset) { idx, dur in
                                VStack(spacing: 2) {
                                    Text("L\(idx + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(Formatters.duration(dur))
                                        .font(.caption.monospacedDigit().bold())
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.green.opacity(0.15), in: Capsule())
                            }
                        }
                    }
                }
            }
        } else {
            VStack(spacing: 18) {
                Label("Distance Run", systemImage: "ruler")
                    .font(.headline)

                VStack(spacing: 4) {
                    Text(Formatters.duration(totalElapsed))
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("elapsed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 32) {
                    statCell(value: Formatters.distance(sessionDistance), label: "covered")
                    statCell(value: Formatters.distance(max(0, targetMeters - sessionDistance)), label: "remaining")
                }
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var completedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(completedTitle)
                .font(.title2.bold())
            HStack(spacing: 16) {
                Label(Formatters.duration(totalElapsed), systemImage: "clock")
                Label(Formatters.distance(sessionDistance), systemImage: "ruler")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            if targetLaps > 1 && !liveLapDurations.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(liveLapDurations.enumerated()), id: \.offset) { idx, dur in
                        VStack(spacing: 2) {
                            Text("L\(idx + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(Formatters.duration(dur))
                                .font(.caption.monospacedDigit().bold())
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var completedTitle: String {
        guard didAutoStop else { return "Session Saved" }
        switch sessionMode {
        case .laps: return targetLaps > 1 ? "All Laps Complete!" : "Lap Complete!"
        case .distance: return "Distance Reached!"
        }
    }

    // MARK: - Gate (full-screen map + floating overlays)

    @ViewBuilder
    private var gateMapFullScreen: some View {
        if route.startCoordinate != nil {
            Map(position: $cameraPosition) {
                if let start = route.startCoordinate {
                    MapCircle(center: start, radius: startToleranceMeters)
                        .foregroundStyle(Color.green.opacity(0.25))
                        .stroke(Color.green, lineWidth: 3)

                    Annotation("Start", coordinate: start) {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 28, height: 28)
                                .shadow(radius: 2)
                            Image(systemName: "flag.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }

                if route.definitionPoints.count >= 2 {
                    MapPolyline(coordinates: route.sortedDefinitionPoints.map(\.coordinate))
                        .stroke(Color.blue.opacity(0.7), lineWidth: 4)
                }

                // Orange dashed "guide" from the user toward the start, with an arrow
                // along the line pointing at the start. Hidden once inside tolerance.
                if let arrow = guidanceArrow {
                    MapPolyline(coordinates: [arrow.userCoord, arrow.startCoord])
                        .stroke(
                            Color.orange,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [5, 8])
                        )

                    Annotation("", coordinate: arrow.arrowCoord) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.orange)
                            .shadow(color: .white, radius: 2)
                            .rotationEffect(.degrees(arrow.bearing))
                    }
                }

                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
        } else {
            Color(.systemGroupedBackground)
                .overlay {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("This route has no defined path.")
                            .font(.callout)
                    }
                    .padding()
                }
        }
    }

    @ViewBuilder
    private var gateStatusBanner: some View {
        if route.startCoordinate != nil {
            HStack(spacing: 14) {
                Image(systemName: gateStatusIcon)
                    .font(.title3.bold())
                Text(gateStatusMessage)
                    .font(.callout.bold())
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(gateDistanceColor, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        }
    }

    private var gateStatusIcon: String {
        guard let d = distanceToStart else { return "location.viewfinder" }
        return d <= startToleranceMeters ? "checkmark.circle.fill" : "figure.walk"
    }

    private var gateStatusMessage: String {
        guard let d = distanceToStart else { return "Acquiring GPS…" }
        if d <= startToleranceMeters { return "You're at the start — press Start!" }
        let dist = Formatters.distance(d)
        return d <= 60
            ? "Almost there! Walk \(dist) closer to start."
            : "You are too far away! Walk \(dist) closer to start."
    }

    private func centerCameraOnStartIfNeeded() {
        guard !didCenterCamera, let start = route.startCoordinate else { return }
        cameraPosition = .region(MKCoordinateRegion(
            center: start,
            latitudinalMeters: 150,
            longitudinalMeters: 150
        ))
        didCenterCamera = true
    }

    // MARK: - Action pill (toolbar) + Done button (completed)

    @ViewBuilder
    private var actionToolbarPill: some View {
        if hasSaved {
            EmptyView()
        } else if isSessionActive {
            Button {
                stopAndSave(auto: false)
            } label: {
                actionPillLabel(text: "Stop", icon: "stop.fill", background: .red)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                startCountdown()
            } label: {
                actionPillLabel(
                    text: "Start",
                    icon: "play.fill",
                    background: isWithinStartTolerance ? Color.green : Color.gray.opacity(0.55)
                )
            }
            .buttonStyle(.plain)
            .disabled(!isWithinStartTolerance)
        }
    }

    private func actionPillLabel(text: String, icon: String, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.callout.bold())
            Text(text)
                .font(.callout.bold())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(background, in: Capsule())
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .frame(width: 180, height: 60)
                .background(Color.accentColor, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var authorizationFootnote: some View {
        switch tracker.authorizationStatus {
        case .denied, .restricted:
            Text("Location access denied. Enable it in Settings to record a session.")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    // MARK: - Countdown overlay

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Get ready…")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))

                if countdownRemaining > 0 {
                    Text("\(countdownRemaining)")
                        .font(.system(size: 160, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: countdownRemaining)
                } else {
                    Text("GO!")
                        .font(.system(size: 110, weight: .heavy, design: .rounded))
                        .foregroundStyle(.green)
                }

                HStack(spacing: 52) {
                    Button {
                        if countdownRemaining <= 1 {
                            countdownTask?.cancel()
                            withAnimation { isCountingDown = false }
                            beginSession()
                        } else {
                            withAnimation { countdownRemaining -= 1 }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { countdownRemaining += 1 }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func startCountdown() {
        countdownRemaining = 5
        withAnimation { isCountingDown = true }
        countdownTask = Task { @MainActor in
            while countdownRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if countdownRemaining > 0 {
                    withAnimation { countdownRemaining -= 1 }
                    UIImpactFeedbackGenerator(style: countdownRemaining == 0 ? .heavy : .medium)
                        .impactOccurred()
                }
            }
            guard !Task.isCancelled else { isCountingDown = false; return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation { isCountingDown = false }
            beginSession()
        }
    }

    private func beginSession() {
        surgeSession = SurgeSession.currentOrNew(in: modelContext)
        let n = Date()
        sessionStartIndex = tracker.recordedLocations.count
        currentLapStartIndex = tracker.recordedLocations.count
        startedAt = n
        currentLapStartedAt = n
        lapCompletions = []
        announcedSegmentsInLap = []
        didAutoStop = false
    }

    private func stopAndSave(auto: Bool) {
        tracker.stop()
        didAutoStop = auto
        saveSession()
    }

    private func evaluateAutoStop() {
        guard isSessionActive else { return }

        if sessionMode == .distance {
            if sessionDistance >= targetMeters { stopAndSave(auto: true) }
            return
        }

        let routeDistance = route.distanceMeters
        guard routeDistance > 0 else { return }
        guard currentLapDistance >= routeDistance else { return }

        // Current lap complete (distance-only — no return-to-start check).
        lapCompletions.append(Date())

        if lapCompletions.count >= targetLaps {
            stopAndSave(auto: true)
        } else {
            // Start the next lap.
            currentLapStartedAt = Date()
            currentLapStartIndex = tracker.recordedLocations.count
            announcedSegmentsInLap = []
        }
    }

    private func checkSegmentBoundaries() {
        guard isSessionActive else { return }
        let ends = route.segmentEndDistances
        // Only interior boundaries trigger turnaround alerts; the final one is the lap end.
        guard ends.count > 1 else { return }
        let segments = route.sortedSegments
        let interior = ends.dropLast()
        for (idx, threshold) in interior.enumerated() {
            if !announcedSegmentsInLap.contains(idx) && currentLapDistance >= threshold {
                announcedSegmentsInLap.insert(idx)
                let direction = SegmentDirection(rawValue: segments[idx].endLabel) ?? .around
                fireTurnaroundAlert(direction: direction)
            }
        }
    }

    private func fireTurnaroundAlert(direction: SegmentDirection) {
        turnaroundAlertDirection = direction
        // Strong haptic burst.
        Task { @MainActor in
            let warning = UINotificationFeedbackGenerator()
            warning.notificationOccurred(.warning)
            let impact = UIImpactFeedbackGenerator(style: .heavy)
            for _ in 0..<3 {
                try? await Task.sleep(for: .milliseconds(200))
                impact.impactOccurred()
            }
        }
        // Visual overlay for ~3 seconds.
        withAnimation(.easeIn(duration: 0.15)) {
            turnaroundAlertVisible = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeOut(duration: 0.4)) {
                turnaroundAlertVisible = false
            }
        }
    }

    private func saveSession() {
        guard !hasSaved, let startedAt, !sessionLocations.isEmpty else {
            hasSaved = true
            return
        }
        let session = Session(startedAt: startedAt, targetLaps: targetLaps)
        session.workoutType = .run
        session.workoutMeasure = sessionMode == .laps ? .laps : .meters
        session.targetValue = sessionMode == .laps ? Double(targetLaps) : targetMeters
        session.endedAt = Date()
        session.lapCompletedAt = lapCompletions
        for location in sessionLocations {
            let point = SessionPoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: location.speed,
                horizontalAccuracy: location.horizontalAccuracy
            )
            session.points.append(point)
        }
        route.sessions.append(session)
        if let surge = surgeSession {
            session.surgeSession = surge
            surge.sessions.append(session)
        }
        modelContext.insert(session)
        hasSaved = true
    }
}

#Preview {
    NavigationStack {
        SessionRecordingView(route: Route(name: "Backyard 1k"))
    }
    .modelContainer(for: Route.self, inMemory: true)
}
