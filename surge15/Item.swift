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

    var startCoordinate: CLLocationCoordinate2D? {
        sortedDefinitionPoints.first?.coordinate
    }

    var distanceMeters: Double {
        Self.totalDistance(coordinates: sortedDefinitionPoints.map(\.coordinate))
    }

    var bestSessionDuration: TimeInterval? {
        sessions.compactMap(\.durationSeconds).min()
    }

    var averageSessionDuration: TimeInterval? {
        let durations = sessions.compactMap(\.durationSeconds)
        guard !durations.isEmpty else { return nil }
        return durations.reduce(0, +) / Double(durations.count)
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
    var route: Route?

    @Relationship(deleteRule: .cascade, inverse: \SessionPoint.session)
    var points: [SessionPoint] = []

    init(startedAt: Date = Date()) {
        self.startedAt = startedAt
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
