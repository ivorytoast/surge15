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

struct SessionRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var route: Route

    @State private var tracker = LocationTracker()

    // Session-level
    @State private var startedAt: Date?
    @State private var sessionStartIndex: Int = 0
    @State private var targetLaps: Int = 1

    // Per-lap
    @State private var currentLapStartedAt: Date?
    @State private var currentLapStartIndex: Int = 0
    @State private var lapCompletions: [Date] = []

    // UI
    @State private var now = Date()
    @State private var hasSaved = false
    @State private var didAutoStop = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var didCenterCamera = false

    // Segment alerts
    @State private var announcedSegmentsInLap: Set<Int> = []
    @State private var turnaroundAlertVisible = false

    private let startToleranceMeters: CLLocationDistance = 20
    private let maxLaps: Int = 20

    var body: some View {
        ZStack {
            VStack(spacing: 16) {
                Text(route.name)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                if isGateState {
                    gateMap
                    gateStatusLine
                    lapPicker
                    Spacer(minLength: 8)
                } else {
                    Spacer()
                    statusBlock
                    Spacer()
                }

                actionButton
                authorizationFootnote
            }
            .padding()

            if turnaroundAlertVisible {
                turnaroundOverlay
                    .transition(.opacity)
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            tracker.requestAuthorization()
            if !tracker.isRecording {
                tracker.start()
            }
            centerCameraOnStartIfNeeded()
        }
        .onChange(of: tracker.recordedLocations.count) { _, _ in
            checkSegmentBoundaries()
            evaluateAutoStop()
            centerCameraOnStartIfNeeded()
        }
        .onDisappear {
            if isSessionActive { saveSession() }
            tracker.stop()
        }
    }

    private var turnaroundOverlay: some View {
        ZStack {
            Color.orange.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 140))
                    .foregroundStyle(.white)
                Text("TURN AROUND")
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

    private var activeBlock: some View {
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
        return targetLaps > 1 ? "All Laps Complete!" : "Lap Complete!"
    }

    // MARK: - Gate (map + status + lap picker)

    @ViewBuilder
    private var gateMap: some View {
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

                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isWithinStartTolerance ? Color.green : Color.secondary.opacity(0.2), lineWidth: 2)
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("This route has no defined path.")
                    .font(.callout)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var gateStatusLine: some View {
        if route.startCoordinate == nil {
            EmptyView()
        } else if let d = distanceToStart {
            if d <= startToleranceMeters {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("At Start — ready to go")
                        .font(.title3.bold())
                }
            } else {
                VStack(spacing: 2) {
                    Text(Formatters.distance(d))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("Walk to the green zone to start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Label("Acquiring GPS…", systemImage: "location.viewfinder")
                .foregroundStyle(.secondary)
        }
    }

    private var lapPicker: some View {
        HStack(spacing: 20) {
            Button {
                if targetLaps > 1 { targetLaps -= 1 }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)
            .disabled(targetLaps <= 1)
            .foregroundStyle(targetLaps <= 1 ? Color.secondary : Color.accentColor)

            VStack(spacing: 0) {
                Text("\(targetLaps)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(targetLaps == 1 ? "lap" : "laps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 70)

            Button {
                if targetLaps < maxLaps { targetLaps += 1 }
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32))
            }
            .buttonStyle(.plain)
            .disabled(targetLaps >= maxLaps)
            .foregroundStyle(targetLaps >= maxLaps ? Color.secondary : Color.accentColor)
        }
        .padding(.vertical, 4)
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

    // MARK: - Action button

    @ViewBuilder
    private var actionButton: some View {
        if hasSaved {
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
        } else if isSessionActive {
            Button {
                stopAndSave(auto: false)
            } label: {
                Text("Stop")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 180)
                    .background(Color.red, in: Circle())
            }
            .buttonStyle(.plain)
        } else {
            Button {
                beginSession()
            } label: {
                Text("Start")
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .frame(width: 180, height: 180)
                    .background(isWithinStartTolerance ? Color.green : Color.gray.opacity(0.5), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!isWithinStartTolerance)
        }
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

    // MARK: - Actions

    private func beginSession() {
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
        let interior = ends.dropLast()
        for (idx, threshold) in interior.enumerated() {
            if !announcedSegmentsInLap.contains(idx) && currentLapDistance >= threshold {
                announcedSegmentsInLap.insert(idx)
                fireTurnaroundAlert()
            }
        }
    }

    private func fireTurnaroundAlert() {
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
