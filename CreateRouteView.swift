//
//  CreateRouteView.swift
//  surge15
//
//  One-time setup: walk or run a loop to define a Route template.
//  While recording, the user can tap "Mark Turnaround" each time they reach a
//  point where, during a session, they should be told to change direction.
//  Each turnaround ends one segment and starts the next.
//

import SwiftUI
import SwiftData
import CoreLocation

struct CreateRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var tracker = LocationTracker()
    @State private var showingSavePrompt = false
    @State private var showingTooShortAlert = false
    @State private var routeName = ""
    /// Cumulative recorded distance at the moment the user tapped "Mark Turnaround".
    @State private var segmentBoundaries: [Double] = []

    private let minimumDistanceMeters: Double = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                instructions
                statusBlock
                Spacer()
                if tracker.isRecording {
                    markTurnaroundButton
                }
                recordButton
                authorizationFootnote
                Spacer()
            }
            .padding()
            .navigationTitle("New Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if tracker.isRecording { tracker.stop() }
                        dismiss()
                    }
                }
            }
            .alert("Name Your Route", isPresented: $showingSavePrompt) {
                TextField("Backyard 1k", text: $routeName)
                Button("Save") { saveAndDismiss() }
                Button("Discard", role: .destructive) { dismiss() }
            } message: {
                Text("Give this loop a name. You'll train on it later.")
            }
            .alert("Route Too Short", isPresented: $showingTooShortAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("A route must be at least \(Int(minimumDistanceMeters)) m. You captured \(Formatters.distance(currentDistance)). Tap Start to try again.")
            }
            .onAppear { tracker.requestAuthorization() }
        }
    }

    private var instructions: some View {
        Text("Walk or run your loop once. Tap **Mark Turnaround** every time you reach a point where you'll need to change direction during a session.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var statusBlock: some View {
        VStack(spacing: 8) {
            Text(tracker.isRecording ? "Recording loop…" : "Ready")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(Formatters.distance(currentDistance))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(meetsMinimum ? .primary : .secondary)
            HStack(spacing: 6) {
                Image(systemName: meetsMinimum ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(meetsMinimum ? .green : .secondary)
                Text("Minimum \(Int(minimumDistanceMeters)) m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            segmentSummary
        }
    }

    @ViewBuilder
    private var segmentSummary: some View {
        let segmentCount = segmentBoundaries.count + 1
        let labels = previewSegmentDistances.enumerated().map { idx, dist in
            "S\(idx + 1): \(Formatters.distance(dist))"
        }
        VStack(spacing: 4) {
            Text("\(segmentCount) segment\(segmentCount == 1 ? "" : "s")")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if !labels.isEmpty {
                Text(labels.joined(separator: " · "))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top, 4)
    }

    /// Distances of each segment captured so far (including the in-progress segment).
    private var previewSegmentDistances: [Double] {
        var prev: Double = 0
        var result: [Double] = []
        for boundary in segmentBoundaries {
            result.append(boundary - prev)
            prev = boundary
        }
        result.append(max(0, currentDistance - prev))
        return result
    }

    private var currentDistance: Double {
        Route.totalDistance(coordinates: tracker.recordedLocations.map(\.coordinate))
    }

    private var meetsMinimum: Bool {
        currentDistance >= minimumDistanceMeters
    }

    private var markTurnaroundButton: some View {
        Button {
            markTurnaround()
        } label: {
            Label("Mark Turnaround", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.orange, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(currentDistance < minimumDistanceMeters || currentDistance <= (segmentBoundaries.last ?? 0))
    }

    private var recordButton: some View {
        Button {
            if tracker.isRecording {
                tracker.stop()
                if meetsMinimum {
                    showingSavePrompt = true
                } else {
                    showingTooShortAlert = true
                }
            } else {
                segmentBoundaries.removeAll()
                tracker.start()
            }
        } label: {
            Text(tracker.isRecording ? "Stop" : "Start")
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: 180, height: 180)
                .background(tracker.isRecording ? Color.red : Color.green, in: Circle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var authorizationFootnote: some View {
        switch tracker.authorizationStatus {
        case .denied, .restricted:
            Text("Location access denied. Enable it in Settings to record a route.")
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        default:
            EmptyView()
        }
    }

    private func markTurnaround() {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        segmentBoundaries.append(currentDistance)
    }

    private func saveAndDismiss() {
        let trimmed = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = Route(name: trimmed.isEmpty ? "Untitled Route" : trimmed)
        let total = currentDistance

        // Build segments from the captured boundaries (+ implicit final segment).
        var prev: Double = 0
        for (idx, boundary) in segmentBoundaries.enumerated() {
            let segment = RouteSegment(
                order: idx,
                distanceMeters: max(0, boundary - prev),
                endLabel: "Turnaround"
            )
            route.segments.append(segment)
            prev = boundary
        }
        let lastSegment = RouteSegment(
            order: segmentBoundaries.count,
            distanceMeters: max(0, total - prev),
            endLabel: "End"
        )
        route.segments.append(lastSegment)

        // Store the GPS trace for visualization.
        for location in tracker.recordedLocations {
            let point = RoutePoint(
                timestamp: location.timestamp,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                speed: location.speed,
                horizontalAccuracy: location.horizontalAccuracy
            )
            route.definitionPoints.append(point)
        }
        modelContext.insert(route)
        dismiss()
    }
}

#Preview {
    CreateRouteView()
        .modelContainer(for: Route.self, inMemory: true)
}
