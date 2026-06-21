//
//  Item.swift
//  surge15
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Route

@Model
final class Route {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \RoutePoint.route)
    var definitionPoints: [RoutePoint] = []

    @Relationship(deleteRule: .cascade, inverse: \Session.route)
    var sessions: [Session] = []

    @Relationship(deleteRule: .cascade, inverse: \RouteSegment.route)
    var segments: [RouteSegment] = []

    init(name: String, createdAt: Date = Date()) {
        self.name = name
        self.createdAt = createdAt
    }

    var sortedDefinitionPoints: [RoutePoint] {
        definitionPoints.sorted { $0.timestamp < $1.timestamp }
    }

    var sortedSessions: [Session] {
        sessions.sorted { $0.startedAt > $1.startedAt }
    }

    var sortedSegments: [RouteSegment] {
        segments.sorted { $0.order < $1.order }
    }

    var startCoordinate: CLLocationCoordinate2D? {
        sortedDefinitionPoints.first?.coordinate
    }

    /// Total lap distance. Uses segments when present; otherwise falls back to the
    /// raw GPS-trace length (legacy single-segment routes).
    var distanceMeters: Double {
        if !segments.isEmpty {
            return sortedSegments.map(\.distanceMeters).reduce(0, +)
        }
        return Self.totalDistance(coordinates: sortedDefinitionPoints.map(\.coordinate))
    }

    /// Cumulative distance at the end of each segment. The last entry equals `distanceMeters`.
    /// All but the last are "interior" boundaries that should trigger a turnaround alert.
    var segmentEndDistances: [Double] {
        var cumulative: Double = 0
        return sortedSegments.map { seg in
            cumulative += seg.distanceMeters
            return cumulative
        }
    }

    var bestLapDuration: TimeInterval? {
        sessions.flatMap(\.lapDurations).min()
    }

    var averageLapDuration: TimeInterval? {
        let allLapDurations = sessions.flatMap(\.lapDurations)
        guard !allLapDurations.isEmpty else { return nil }
        return allLapDurations.reduce(0, +) / Double(allLapDurations.count)
    }

    static func totalDistance(coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<coordinates.count {
            let a = CLLocation(latitude: coordinates[i - 1].latitude, longitude: coordinates[i - 1].longitude)
            let b = CLLocation(latitude: coordinates[i].latitude, longitude: coordinates[i].longitude)
            total += b.distance(from: a)
        }
        return total
    }
}

// MARK: - RoutePoint (defines a route's shape)

@Model
final class RoutePoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var horizontalAccuracy: Double
    var route: Route?

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        speed: Double = 0,
        horizontalAccuracy: Double = 0
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - RouteSegment (a leg between turnarounds)

@Model
final class RouteSegment {
    var order: Int
    var distanceMeters: Double
    /// What kind of boundary ends this segment ("Turnaround", "End", etc.).
    var endLabel: String
    var route: Route?

    init(order: Int, distanceMeters: Double, endLabel: String) {
        self.order = order
        self.distanceMeters = distanceMeters
        self.endLabel = endLabel
    }
}

// MARK: - Geo helpers

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        let a = CLLocation(latitude: latitude, longitude: longitude)
        let b = CLLocation(latitude: other.latitude, longitude: other.longitude)
        return a.distance(from: b)
    }
}

// MARK: - Session (one execution of a route)

@Model
final class Session {
    var startedAt: Date
    var endedAt: Date?
    var targetLaps: Int = 1
    /// Timestamps marking the completion of each lap, in order. Empty for legacy single-lap sessions.
    var lapCompletedAt: [Date] = []
    var route: Route?

    @Relationship(deleteRule: .cascade, inverse: \SessionPoint.session)
    var points: [SessionPoint] = []

    init(startedAt: Date = Date(), targetLaps: Int = 1) {
        self.startedAt = startedAt
        self.targetLaps = targetLaps
    }

    var sortedPoints: [SessionPoint] {
        points.sorted { $0.timestamp < $1.timestamp }
    }

    var durationSeconds: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }

    var distanceMeters: Double {
        Route.totalDistance(coordinates: sortedPoints.map(\.coordinate))
    }

    /// Pace in seconds per kilometer.
    var paceSecondsPerKilometer: Double? {
        guard let duration = durationSeconds, distanceMeters > 0 else { return nil }
        return duration / (distanceMeters / 1000)
    }

    /// Durations per completed lap. Falls back to one "lap" equal to the session duration
    /// for legacy sessions that pre-date lap tracking.
    var lapDurations: [TimeInterval] {
        if !lapCompletedAt.isEmpty {
            var result: [TimeInterval] = []
            var prev = startedAt
            for ts in lapCompletedAt.sorted() {
                result.append(ts.timeIntervalSince(prev))
                prev = ts
            }
            return result
        } else if let duration = durationSeconds {
            return [duration]
        }
        return []
    }
}

// MARK: - SessionPoint (a sample within a session)

@Model
final class SessionPoint {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var speed: Double
    var horizontalAccuracy: Double
    var session: Session?

    init(
        timestamp: Date,
        latitude: Double,
        longitude: Double,
        altitude: Double = 0,
        speed: Double = 0,
        horizontalAccuracy: Double = 0
    ) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.speed = speed
        self.horizontalAccuracy = horizontalAccuracy
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
