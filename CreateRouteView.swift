//
//  CreateRouteView.swift
//  surge15
//
//  One-time setup: walk a loop to define a Route template.
//  Live map shows the walked path; tapping "Mark Turnaround" drops a green pin.
//

import SwiftUI
import SwiftData
import CoreLocation
import MapKit

struct CreateRouteView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var tracker = LocationTracker()
    @State private var cameraPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    @State private var isRecording = false
    /// Initially true so the overlay covers the screen the instant the view loads.
    /// Flipped false after a short delay in `onAppear` so the GPS has time to settle.
    @State private var isAcquiringGPS = true
    @State private var recordingStartIndex = 0

    private let acquiringDelaySeconds: Double = 2.5

    /// Cumulative recorded distance at the moment the user tapped "Mark Turnaround".
    @State private var segmentBoundaries: [Double] = []
    /// Coordinates corresponding to each segment boundary, for map pin display.
    @State private var turnaroundCoordinates: [CLLocationCoordinate2D] = []

    @State private var showingSavePrompt = false
    @State private var showingTooShortAlert = false
    @State private var routeName = ""

    private let minimumDistanceMeters: Double = 10

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 12) {
                    mapView
                        .frame(minHeight: 320, maxHeight: .infinity)

                    if !turnaroundCoordinates.isEmpty {
                        turnaroundPills
                    }

                    if isRecording {
                        markTurnaroundButton
                    }

                    recordButton

                    authorizationFootnote
                }
                .padding()

                if isAcquiringGPS {
                    acquiringOverlay
                        .transition(.opacity)
                }
            }
            .navigationTitle("New Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isRecording = false
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
            .onAppear {
                tracker.requestAuthorization()
                if !tracker.isRecording {
                    tracker.start()
                }
                // Let the GPS settle for a couple seconds before showing UI to the user.
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(acquiringDelaySeconds))
                    withAnimation(.easeOut(duration: 0.3)) {
                        isAcquiringGPS = false
                    }
                }
            }
            .onDisappear {
                tracker.stop()
            }
        }
    }

    // MARK: - Map

    private var mapView: some View {
        Map(position: $cameraPosition) {
            if recordedCoordinates.count >= 2 {
                MapPolyline(coordinates: recordedCoordinates)
                    .stroke(Color.blue, lineWidth: 4)
            }

            ForEach(Array(turnaroundCoordinates.enumerated()), id: \.offset) { idx, coord in
                Annotation("T\(idx + 1)", coordinate: coord) {
                    turnaroundPin
                }
            }

            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(alignment: .topLeading) {
            distancePill
                .padding(12)
        }
    }

    private var distancePill: some View {
        Text(Formatters.distance(currentDistance))
            .font(.system(.title2, design: .rounded, weight: .heavy))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.72), in: Capsule())
    }

    private var turnaroundPin: some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(radius: 2)
            Image(systemName: "arrow.uturn.backward")
                .foregroundStyle(.green)
                .font(.system(size: 15, weight: .heavy))
        }
    }

    private var turnaroundPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(turnaroundCoordinates.enumerated()), id: \.offset) { idx, _ in
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption2.weight(.heavy))
                        Text("T\(idx + 1)")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.2), in: Capsule())
                    .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 4)
        }
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
        .disabled(!canMarkTurnaround)
    }

    private var recordButton: some View {
        Button {
            if isRecording {
                stopRecording()
                if meetsMinimum {
                    showingSavePrompt = true
                } else {
                    showingTooShortAlert = true
                }
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "Stop" : "Start")
                .font(.title.bold())
                .foregroundStyle(.white)
                .frame(width: 160, height: 160)
                .background(isRecording ? Color.red : Color.green, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(isAcquiringGPS)
    }

    private var acquiringOverlay: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                Text("Acquiring GPS Location")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Hang tight for a moment…")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
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

    // MARK: - Derived

    private var recordedLocations: [CLLocation] {
        guard recordingStartIndex <= tracker.recordedLocations.count else { return [] }
        return Array(tracker.recordedLocations.dropFirst(recordingStartIndex))
    }

    private var recordedCoordinates: [CLLocationCoordinate2D] {
        recordedLocations.map(\.coordinate)
    }

    private var currentDistance: Double {
        Route.totalDistance(coordinates: recordedCoordinates)
    }

    private var meetsMinimum: Bool {
        currentDistance >= minimumDistanceMeters
    }

    private var canMarkTurnaround: Bool {
        isRecording
        && currentDistance >= minimumDistanceMeters
        && currentDistance > (segmentBoundaries.last ?? 0)
    }

    // MARK: - Actions

    private func startRecording() {
        segmentBoundaries = []
        turnaroundCoordinates = []
        recordingStartIndex = tracker.recordedLocations.count
        isRecording = true
    }

    private func stopRecording() {
        isRecording = false
    }

    private func markTurnaround() {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        segmentBoundaries.append(currentDistance)
        if let last = tracker.recordedLocations.last?.coordinate {
            turnaroundCoordinates.append(last)
        }
    }

    private func saveAndDismiss() {
        let trimmed = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = Route(name: trimmed.isEmpty ? "Untitled Route" : trimmed)
        let total = currentDistance

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

        for location in recordedLocations {
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
