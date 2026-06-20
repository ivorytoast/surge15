//
//  SessionRecordingView.swift
//  surge15
//
//  Executes one Session on an existing Route.
//  - Start is gated until the user is within 20 m of the route's start point.
//  - Auto-stops when the user has traveled at least 80% of the loop distance
//    AND is back within 20 m of the start point.
//

import SwiftUI
import SwiftData
import CoreLocation

struct SessionRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var route: Route

    @State private var tracker = LocationTracker()
    @State private var startedAt: Date?
    @State private var sessionStartIndex: Int = 0
    @State private var now = Date()
    @State private var hasSaved = false
    @State private var didAutoStop = false

    private let startToleranceMeters: CLLocationDistance = 20
    private let autoStopProgressFraction: Double = 0.8

    var body: some View {
        VStack(spacing: 24) {
            Text(route.name)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            statusBlock
            Spacer()
            actionButton
            authorizationFootnote
            Spacer()
        }
        .padding()
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
        }
        .onChange(of: tracker.recordedLocations.count) { _, _ in
            evaluateAutoStop()
        }
        .onDisappear {
            if isSessionActive { saveSession() }
            tracker.stop()
        }
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

    private var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return now.timeIntervalSince(startedAt)
    }

    // MARK: - Status block

    @ViewBuilder
    private var statusBlock: some View {
        if hasSaved {
            completedBlock
        } else if isSessionActive {
            activeBlock
        } else {
            gateBlock
        }
    }

    private var activeBlock: some View {
        VStack(spacing: 8) {
            Text("In Progress")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(Formatters.duration(elapsed))
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 16) {
                Label(Formatters.distance(sessionDistance), systemImage: "ruler")
                Label("\(sessionLocations.count) pts", systemImage: "location.fill")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var completedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text(didAutoStop ? "Lap Complete!" : "Session Saved")
                .font(.title2.bold())
            HStack(spacing: 16) {
                Label(Formatters.duration(elapsed), systemImage: "clock")
                Label(Formatters.distance(sessionDistance), systemImage: "ruler")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var gateBlock: some View {
        VStack(spacing: 8) {
            if route.startCoordinate == nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("This route has no defined path.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            } else if let d = distanceToStart {
                if d <= startToleranceMeters {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    Text("At Start")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(Formatters.distance(d))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "location.north.line.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)
                    Text("Walk to Start")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text(Formatters.distance(d))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("within 20 m to start")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Acquiring GPS…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
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
        sessionStartIndex = tracker.recordedLocations.count
        startedAt = Date()
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
        guard sessionDistance >= routeDistance * autoStopProgressFraction else { return }
        guard let d = distanceToStart, d <= startToleranceMeters else { return }
        stopAndSave(auto: true)
    }

    private func saveSession() {
        guard !hasSaved, let startedAt, !sessionLocations.isEmpty else {
            hasSaved = true
            return
        }
        let session = Session(startedAt: startedAt)
        session.endedAt = Date()
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
