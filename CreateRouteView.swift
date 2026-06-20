//
//  CreateRouteView.swift
//  surge15
//
//  One-time setup: walk or run a loop to define a Route template.
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

    private let minimumDistanceMeters: Double = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                instructions
                Spacer()
                statusBlock
                Spacer()
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
        Text("Walk or run your loop once. The app will remember its shape so you can train on it later.")
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
            Text("\(tracker.recordedLocations.count) points captured")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var meetsMinimum: Bool {
        currentDistance >= minimumDistanceMeters
    }

    private var currentDistance: Double {
        Route.totalDistance(coordinates: tracker.recordedLocations.map(\.coordinate))
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

    private func saveAndDismiss() {
        let trimmed = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        let route = Route(name: trimmed.isEmpty ? "Untitled Route" : trimmed)
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
