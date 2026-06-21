//
//  RouteDetailView.swift
//  surge15
//
//  Shows a Route's summary, past sessions, and the primary "Start Session" action.
//

import SwiftUI
import SwiftData

struct RouteDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var route: Route
    @State private var showingSessionRecorder = false

    var body: some View {
        List {
            Section {
                summaryGrid
                NavigationLink {
                    SessionRecordingView(route: route)
                } label: {
                    Label("Start Session", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listRowBackground(Color.green.opacity(0.15))
            }

            Section("Past Sessions") {
                if route.sessions.isEmpty {
                    Text("No sessions yet. Tap Start Session to begin.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(route.sortedSessions) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            sessionRow(session)
                        }
                    }
                    .onDelete(perform: deleteSessions)
                }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Loop Distance", value: Formatters.distance(route.distanceMeters))
            LabeledContent("Sessions", value: "\(route.sessions.count)")
            if let best = route.bestLapDuration {
                LabeledContent("Best Lap", value: Formatters.duration(best))
            }
            if let avg = route.averageLapDuration {
                LabeledContent("Average Lap", value: Formatters.duration(avg))
            }
            if !route.segments.isEmpty {
                LabeledContent("Segments", value: segmentSummaryString)
            }
            LabeledContent("Created", value: route.createdAt.formatted(date: .abbreviated, time: .shortened))
        }
        .font(.callout)
    }

    private var segmentSummaryString: String {
        let segs = route.sortedSegments
        if segs.count == 1 {
            return "1 (loop)"
        }
        let distances = segs.map { Formatters.distance($0.distanceMeters) }
        return "\(segs.count) · \(distances.joined(separator: " → "))"
    }

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 12) {
                if let duration = session.durationSeconds {
                    Label(Formatters.duration(duration), systemImage: "clock")
                }
                Label("\(session.targetLaps) \(session.targetLaps == 1 ? "lap" : "laps")", systemImage: "flag.checkered")
                if let pace = session.paceSecondsPerKilometer {
                    Label(Formatters.pace(secondsPerKilometer: pace), systemImage: "speedometer")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func deleteSessions(_ offsets: IndexSet) {
        let sorted = route.sortedSessions
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}

#Preview {
    NavigationStack {
        RouteDetailView(route: Route(name: "Backyard 1k"))
    }
    .modelContainer(for: Route.self, inMemory: true)
}
