//
//  SessionDetailView.swift
//  surge15
//

import SwiftUI
import SwiftData

struct SessionDetailView: View {
    let session: Session

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .abbreviated, time: .shortened))
                }
                if let duration = session.durationSeconds {
                    LabeledContent("Duration", value: Formatters.duration(duration))
                }
                LabeledContent("Distance", value: Formatters.distance(session.distanceMeters))
                if let pace = session.paceSecondsPerKilometer {
                    LabeledContent("Pace", value: Formatters.pace(secondsPerKilometer: pace))
                }
                LabeledContent("Points", value: "\(session.points.count)")
            }

            Section("Points") {
                ForEach(session.sortedPoints) { point in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: "%.5f, %.5f", point.latitude, point.longitude))
                            .font(.callout.monospaced())
                        Text(point.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(session: Session())
    }
    .modelContainer(for: Route.self, inMemory: true)
}
