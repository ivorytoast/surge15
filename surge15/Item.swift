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

// MARK: - Plan (a reusable workout template)

@Model
final class Plan {
    var name: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \PlanItem.plan)
    var items: [PlanItem] = []

    init(name: String, createdAt: Date = Date()) {
        self.name = name
        self.createdAt = createdAt
    }

    var sortedItems: [PlanItem] {
        items.sorted { $0.order < $1.order }
    }
}

// MARK: - PlanItem (one entry in a plan: a route + target laps)

@Model
final class PlanItem {
    var order: Int
    var targetLaps: Int
    var route: Route?
    var plan: Plan?

    init(order: Int, targetLaps: Int = 1, route: Route? = nil) {
        self.order = order
        self.targetLaps = targetLaps
        self.route = route
    }
}

// MARK: - SurgeSession (a day's collection of workouts)

@Model
final class SurgeSession {
    /// User-editable label (auto-named on creation, e.g. "Morning · Jun 20").
    var name: String
    /// The day this surge session belongs to, anchored to the start of that day.
    var date: Date
    /// When this surge session was created (used for start-time display + sort).
    var createdAt: Date
    /// When the user manually ended the workout. While nil, this surge session is
    /// eligible to be "current" (subject to the 1-hour idle window).
    var endedAt: Date?
    /// The plan template this surge session was instantiated from, if any.
    var plan: Plan?

    @Relationship(deleteRule: .nullify, inverse: \Session.surgeSession)
    var sessions: [Session] = []

    init(name: String, date: Date, createdAt: Date = Date()) {
        self.name = name
        self.date = date
        self.createdAt = createdAt
    }

    var sortedSessions: [Session] {
        sessions.sorted { $0.startedAt < $1.startedAt }
    }

    var totalDurationSeconds: TimeInterval? {
        let durations = sessions.compactMap(\.durationSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +)
    }

    var totalDistanceMeters: Double {
        sessions.map(\.distanceMeters).reduce(0, +)
    }

    /// Auto-name based on the time of day, e.g. "Morning · Jun 20".
    static func autoName(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let timeOfDay: String
        switch hour {
        case 0..<5: timeOfDay = "Late Night"
        case 5..<11: timeOfDay = "Morning"
        case 11..<14: timeOfDay = "Midday"
        case 14..<17: timeOfDay = "Afternoon"
        case 17..<21: timeOfDay = "Evening"
        default: timeOfDay = "Night"
        }
        return "\(timeOfDay) · \(date.formatted(.dateTime.month().day()))"
    }

    // MARK: - "Current" surge session lifecycle

    /// A surge session expires this long after its last activity.
    static let currentSurgeExpiryInterval: TimeInterval = 3600  // 1 hour

    /// Most recent moment something happened — either creation or the latest attached session start.
    var lastActivityAt: Date {
        max(createdAt, sessions.map(\.startedAt).max() ?? createdAt)
    }

    /// True while this surge session is inside the 1-hour window AND hasn't been manually ended.
    var isCurrent: Bool {
        guard endedAt == nil else { return false }
        return Date().timeIntervalSince(lastActivityAt) < Self.currentSurgeExpiryInterval
    }

    /// Returns the active surge session, or `nil` if every existing surge session has expired.
    static func current(in context: ModelContext) -> SurgeSession? {
        var descriptor = FetchDescriptor<SurgeSession>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        guard let all = try? context.fetch(descriptor) else { return nil }
        return all.first { $0.isCurrent }
    }

    /// Returns the current surge session, or inserts and returns a brand-new auto-named one.
    @discardableResult
    static func currentOrNew(in context: ModelContext) -> SurgeSession {
        if let active = current(in: context) { return active }
        let now = Date()
        let surge = SurgeSession(
            name: autoName(for: now),
            date: Calendar.current.startOfDay(for: now),
            createdAt: now
        )
        context.insert(surge)
        return surge
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
    var surgeSession: SurgeSession?

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
