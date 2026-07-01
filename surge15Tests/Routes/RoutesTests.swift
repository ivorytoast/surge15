//
//  RoutesTests.swift
//  surge15Tests
//

import Testing
import SwiftData
import CoreLocation
@testable import surge15

// MARK: - truncatedRouteName

struct TruncatedRouteNameTests {

    @Test func shortNamePassesThrough() {
        #expect(truncatedRouteName("Park Loop") == "Park Loop")
    }

    @Test func nameAtExactLimitPassesThrough() {
        let name = String(repeating: "a", count: routeNameRowCharLimit)
        #expect(truncatedRouteName(name) == name)
    }

    @Test func nameOneOverLimitIsTruncated() {
        let name = String(repeating: "a", count: routeNameRowCharLimit + 1)
        let expected = String(repeating: "a", count: routeNameRowCharLimit) + "…"
        #expect(truncatedRouteName(name) == expected)
    }

    @Test func longNameIsTruncated() {
        #expect(truncatedRouteName("A Very Long Route Name That Exceeds The Limit") == "A Very Long Rout…")
    }

    @Test func customLimitIsRespected() {
        #expect(truncatedRouteName("Hello World", limit: 5) == "Hello…")
    }

    @Test func emptyNamePassesThrough() {
        #expect(truncatedRouteName("") == "")
    }
}

// MARK: - clusterRoutes

struct ClusterRoutesTests {

    // Full schema so SwiftData can resolve all relationships on Route.
    private func makeContainer() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Route.self, RoutePoint.self, RouteSegment.self,
                Session.self, SessionPoint.self, SurgeSession.self,
                Plan.self, PlanItem.self, PlanGroup.self, CustomExercise.self,
            configurations: config
        )
        return ModelContext(container)
    }

    private func makeRoute(name: String, lat: Double, lon: Double, in context: ModelContext) -> Route {
        let route = Route(name: name)
        let point = RoutePoint(timestamp: Date(), latitude: lat, longitude: lon)
        context.insert(route)
        context.insert(point)
        point.route = route
        return route
    }

    @Test func emptyInputReturnsEmptyResult() throws {
        let result = clusterRoutes([], withinMeters: 100)
        #expect(result.isEmpty)
    }

    @Test func singleRouteFormsSingleCluster() throws {
        let context = try makeContainer()
        let route = makeRoute(name: "A", lat: 40.0, lon: -74.0, in: context)
        let result = clusterRoutes([route], withinMeters: 100)
        #expect(result.count == 1)
        #expect(result[0].routes.count == 1)
    }

    @Test func twoRoutesWithinThresholdMerge() throws {
        let context = try makeContainer()
        let a = makeRoute(name: "A", lat: 40.0000, lon: -74.0, in: context)
        let b = makeRoute(name: "B", lat: 40.0004, lon: -74.0, in: context) // ~44 m away
        let result = clusterRoutes([a, b], withinMeters: 100)
        #expect(result.count == 1)
        #expect(result[0].routes.count == 2)
    }

    @Test func twoRoutesBeyondThresholdStaySeparate() throws {
        let context = try makeContainer()
        let a = makeRoute(name: "A", lat: 40.0000, lon: -74.0, in: context)
        let b = makeRoute(name: "B", lat: 40.0020, lon: -74.0, in: context) // ~222 m away
        let result = clusterRoutes([a, b], withinMeters: 100)
        #expect(result.count == 2)
    }

    // A–B ~66 m (within), B–C ~66 m (within), A–C ~133 m (outside) → all three merge.
    @Test func transitivityGroupsAllThree() throws {
        let context = try makeContainer()
        let a = makeRoute(name: "A", lat: 40.0000, lon: -74.0, in: context)
        let b = makeRoute(name: "B", lat: 40.0006, lon: -74.0, in: context)
        let c = makeRoute(name: "C", lat: 40.0012, lon: -74.0, in: context)
        let result = clusterRoutes([a, b, c], withinMeters: 100)
        #expect(result.count == 1)
        #expect(result[0].routes.count == 3)
    }

    @Test func routeWithNoStartCoordinateIsSkipped() throws {
        let context = try makeContainer()
        let noCoord = Route(name: "No Coord")
        context.insert(noCoord)
        let withCoord = makeRoute(name: "With Coord", lat: 40.0, lon: -74.0, in: context)
        let result = clusterRoutes([noCoord, withCoord], withinMeters: 100)
        #expect(result.count == 1)
        #expect(result[0].routes[0].name == "With Coord")
    }

    @Test func centroidIsAverageOfClusteredCoordinates() throws {
        let context = try makeContainer()
        let a = makeRoute(name: "A", lat: 40.0000, lon: -74.0000, in: context)
        let b = makeRoute(name: "B", lat: 40.0004, lon: -74.0002, in: context) // within 100 m
        let result = clusterRoutes([a, b], withinMeters: 100)
        #expect(result.count == 1)
        let centroid = result[0].coordinate
        #expect(abs(centroid.latitude  - 40.0002)  < 0.00001)
        #expect(abs(centroid.longitude - (-74.0001)) < 0.00001)
    }
}

// MARK: - rdpSmooth
//
// Geometry notes (lat 40°): 1° lon ≈ 85,143 m, 1° lat ≈ 111,000 m.
// All tests use a north–south baseline (constant lon = -74.0) so perpendicular
// distance equals the east–west offset, which is easy to reason about.

struct RdpSmoothTests {

    private func coord(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: Edge cases

    @Test func emptyInputReturnsEmpty() {
        #expect(rdpSmooth([], epsilon: 5).isEmpty)
    }

    @Test func singlePointReturnedUnchanged() {
        let pts = [coord(40.0, -74.0)]
        #expect(rdpSmooth(pts, epsilon: 5).count == 1)
    }

    @Test func twoPointsReturnedUnchanged() {
        let pts = [coord(40.0, -74.0), coord(40.001, -74.0)]
        #expect(rdpSmooth(pts, epsilon: 5).count == 2)
    }

    @Test func zeroEpsilonReturnsAllPoints() {
        let pts = [coord(40.0, -74.0), coord(40.0005, -74.0), coord(40.001, -74.0)]
        #expect(rdpSmooth(pts, epsilon: 0).count == 3)
    }

    // MARK: Simplification

    // Middle point is exactly on the baseline — perpendicular distance = 0.
    @Test func collinearMiddlePointIsRemoved() {
        let pts = [coord(40.0000, -74.0), coord(40.0005, -74.0), coord(40.0010, -74.0)]
        let result = rdpSmooth(pts, epsilon: 5)
        #expect(result.count == 2)
        #expect(result.first!.latitude == 40.0000)
        #expect(result.last!.latitude  == 40.0010)
    }

    // Middle point is ~85 m off the baseline — well above epsilon=5, so it's kept.
    @Test func pointFarOffLineIsKept() {
        let pts = [coord(40.0000, -74.0), coord(40.0005, -74.001), coord(40.0010, -74.0)]
        let result = rdpSmooth(pts, epsilon: 5)
        #expect(result.count == 3)
    }

    // Middle point is ~0.85 m off the baseline — below epsilon=5, so it's removed.
    @Test func pointCloseToLineIsRemoved() {
        let pts = [coord(40.0000, -74.0), coord(40.0005, -74.00001), coord(40.0010, -74.0)]
        let result = rdpSmooth(pts, epsilon: 5)
        #expect(result.count == 2)
    }

    // Four collinear interior points between two endpoints — all removed.
    @Test func multipleCollinearInteriorPointsAllRemoved() {
        let pts = [
            coord(40.0000, -74.0),
            coord(40.0002, -74.0),
            coord(40.0005, -74.0),
            coord(40.0007, -74.0),
            coord(40.0010, -74.0),
        ]
        let result = rdpSmooth(pts, epsilon: 5)
        #expect(result.count == 2)
    }

    // B and D are exact midpoints of the A–C and C–E sub-segments respectively,
    // so their perpendicular distances from those sub-lines ≈ 0 → removed.
    // C is ~85 m off the overall A–E line → kept.
    // Result: [A, C, E].
    @Test func midpointNeighboursOfDeviationAreRemoved() {
        let pts = [
            coord(40.0000, -74.0000),   // A
            coord(40.0002, -74.0005),   // B — midpoint of A–C, removed
            coord(40.0004, -74.0010),   // C — ~85 m off A–E, kept
            coord(40.0007, -74.0005),   // D — midpoint of C–E, removed
            coord(40.0010, -74.0000),   // E
        ]
        let result = rdpSmooth(pts, epsilon: 5)
        #expect(result.count == 3)
        #expect(abs(result[1].longitude - (-74.001)) < 0.000001)
    }
}
