//
//  RouteShareService.swift
//  surge15
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Service

struct RouteShareService {
    private static let baseURL = "https://surge15.app"

    // MARK: Share (upload route → get code)

    static func share(_ route: Route) async throws -> String {
        let url = URL(string: "\(baseURL)/share")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ShareRequest(
            name: route.name,
            points: route.sortedDefinitionPoints.map {
                ShareRequest.Point(lat: $0.latitude, lng: $0.longitude, alt: $0.altitude)
            },
            segments: route.segments.isEmpty ? nil : route.sortedSegments.map {
                ShareRequest.Segment(order: $0.order, distanceMeters: $0.distanceMeters, endLabel: $0.endLabel)
            }
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ShareError.serverError
        }
        return try JSONDecoder().decode(ShareResponse.self, from: data).code
    }

    // MARK: Import (code → Route saved to SwiftData)

    static func importRoute(code: String, into context: ModelContext) async throws -> Route {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let url = URL(string: "\(baseURL)/import?code=\(trimmed)") else {
            throw ShareError.serverError
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200:  break
        case 404:  throw ShareError.notFound
        case 410:  throw ShareError.expired
        default:   throw ShareError.serverError
        }

        let result = try JSONDecoder().decode(ImportResponse.self, from: data)

        let route = Route(name: result.name)
        for (i, p) in result.points.enumerated() {
            route.definitionPoints.append(RoutePoint(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                latitude: p.lat,
                longitude: p.lng,
                altitude: p.alt ?? 0
            ))
        }
        result.segments?.forEach { seg in
            route.segments.append(RouteSegment(
                order: seg.order,
                distanceMeters: seg.distanceMeters,
                endLabel: seg.endLabel
            ))
        }
        context.insert(route)
        return route
    }

    // MARK: Share message

    static func shareMessage(code: String) -> String {
        """
        Here's my surge15 track! Open surge15, go to Settings → Import Route, and enter this code:

        \(code)

        This code expires in 48 hours.
        """
    }

    // MARK: Errors

    enum ShareError: LocalizedError {
        case notFound, expired, serverError

        var errorDescription: String? {
            switch self {
            case .notFound:    return "Code not found. Check it and try again."
            case .expired:     return "This code has expired. Ask for a new one."
            case .serverError: return "Something went wrong. Try again later."
            }
        }
    }
}

// MARK: - Encodable request types

private struct ShareRequest: Encodable {
    let name: String
    let points: [Point]
    let segments: [Segment]?

    struct Point: Encodable {
        let lat: Double
        let lng: Double
        let alt: Double
    }

    struct Segment: Encodable {
        let order: Int
        let distanceMeters: Double
        let endLabel: String
    }
}

private struct ShareResponse: Decodable {
    let code: String
}

// MARK: - Decodable response types

private struct ImportResponse: Decodable {
    let name: String
    let points: [Point]
    let segments: [Segment]?

    struct Point: Decodable {
        let lat: Double
        let lng: Double
        let alt: Double?
    }

    struct Segment: Decodable {
        let order: Int
        let distanceMeters: Double
        let endLabel: String
    }
}

// MARK: - Share sheet helper

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
}

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
