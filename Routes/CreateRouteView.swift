//
//  CreateRouteView.swift
//  surge15
//
//  Full-screen map: blue polyline traces your path, green pins drop at each
//  direction tap. The Record / Stop control lives in the nav bar; the L / U / R
//  direction pad floats over the bottom of the map while recording.
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
    @State private var isAcquiringGPS = true
    @State private var recordingStartIndex = 0

    @State private var segmentBoundaries: [Double] = []
    @State private var segmentDirections: [SegmentDirection] = []
    @State private var turnaroundCoordinates: [CLLocationCoordinate2D] = []

    @State private var showingSavePrompt = false
    @State private var showingTooShortAlert = false
    @State private var routeName = ""

    private let minimumDistanceMeters: Double = 10
    private let acquiringDelaySeconds: Double = 2.5

    var body: some View {
        NavigationStack {
            ZStack {
                mapView
                    .ignoresSafeArea(edges: .bottom)

                VStack(spacing: 0) {
                    Spacer()
                    if !segmentBoundaries.isEmpty {
                        turnaroundPills
                            .padding(.bottom, 10)
                    }
                    if isRecording {
                        directionRow
                    }
                }
                .padding(.bottom, 22)

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
                ToolbarItem(placement: .topBarTrailing) {
                    recordButton
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
                Text("A route must be at least \(Int(minimumDistanceMeters)) m. You captured \(Formatters.distance(currentDistance)). Tap Record to try again.")
            }
            .onAppear {
                tracker.requestAuthorization()
                if !tracker.isRecording {
                    tracker.start()
                }
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
                let dir = segmentDirections.indices.contains(idx) ? segmentDirections[idx] : .around
                Annotation("\(idx + 1)", coordinate: coord) {
                    pin(direction: dir)
                }
            }

            UserAnnotation()
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .topLeading) {
            distancePill
                .padding(.horizontal, 16)
                .padding(.top, 8)
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

    private func pin(direction: SegmentDirection) -> some View {
        ZStack {
            Circle()
                .fill(.white)
                .frame(width: 30, height: 30)
                .shadow(radius: 2)
            Image(systemName: direction.padIcon)
                .foregroundStyle(.green)
                .font(.system(size: 14, weight: .heavy))
        }
    }

    // MARK: - Overlays

    private var turnaroundPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<segmentBoundaries.count, id: \.self) { idx in
                    let dir = segmentDirections.indices.contains(idx) ? segmentDirections[idx] : .around
                    HStack(spacing: 4) {
                        Image(systemName: dir.padIcon)
                            .font(.caption2.weight(.heavy))
                        Text("\(idx + 1)")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.65), in: Capsule())
                    .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private var directionRow: some View {
        HStack(spacing: 18) {
            directionButton(.left)
            directionButton(.around)
            directionButton(.right)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }

    private func directionButton(_ dir: SegmentDirection) -> some View {
        Button {
            markBoundary(direction: dir)
        } label: {
            Image(systemName: dir.padIcon)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.orange, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(!canMarkBoundary)
        .opacity(canMarkBoundary ? 1 : 0.5)
    }

    // MARK: - Toolbar record button

    private var recordButton: some View {
        Button {
            handleRecordTap()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isRecording ? "stop.fill" : "record.circle.fill")
                    .font(.callout.bold())
                Text(isRecording ? "Stop" : "Record")
                    .font(.callout.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isAcquiringGPS)
    }

    private func handleRecordTap() {
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

    private var canMarkBoundary: Bool {
        isRecording
        && currentDistance >= minimumDistanceMeters
        && currentDistance > (segmentBoundaries.last ?? 0)
    }

    // MARK: - Actions

    private func startRecording() {
        segmentBoundaries = []
        segmentDirections = []
        turnaroundCoordinates = []
        recordingStartIndex = tracker.recordedLocations.count
        isRecording = true
    }

    private func stopRecording() {
        isRecording = false
    }

    private func markBoundary(direction: SegmentDirection) {
        let haptic = UIImpactFeedbackGenerator(style: .medium)
        haptic.impactOccurred()
        segmentBoundaries.append(currentDistance)
        segmentDirections.append(direction)
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
            let dir = segmentDirections.indices.contains(idx) ? segmentDirections[idx] : .around
            let segment = RouteSegment(
                order: idx,
                distanceMeters: max(0, boundary - prev),
                endLabel: dir.rawValue
            )
            route.segments.append(segment)
            prev = boundary
        }
        let lastSegment = RouteSegment(
            order: segmentBoundaries.count,
            distanceMeters: max(0, total - prev),
            endLabel: SegmentDirection.end.rawValue
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
