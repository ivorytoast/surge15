//
//  RouteSmoothing.swift
//  surge15
//
//  Ramer-Douglas-Peucker simplification for GPS polylines.
//  Epsilon is in meters. Higher = more aggressive smoothing.
//

import CoreLocation

/// Epsilon used everywhere a route polyline is rendered in the app.
let routeDisplayEpsilon: Double = 5.0

// MARK: - RDP

/// Simplify a GPS polyline using Ramer-Douglas-Peucker.
/// Points within `epsilon` metres of the connecting line are removed.
func rdpSmooth(_ coords: [CLLocationCoordinate2D], epsilon: Double) -> [CLLocationCoordinate2D] {
    guard coords.count > 2, epsilon > 0 else { return coords }
    var maxDist = 0.0
    var splitIndex = 0
    for i in 1..<coords.count - 1 {
        let d = perpendicularDistanceMeters(coords[i], from: coords.first!, to: coords.last!)
        if d > maxDist { maxDist = d; splitIndex = i }
    }
    if maxDist > epsilon {
        let left  = rdpSmooth(Array(coords[...splitIndex]), epsilon: epsilon)
        let right = rdpSmooth(Array(coords[splitIndex...]), epsilon: epsilon)
        return left.dropLast() + right
    }
    return [coords.first!, coords.last!]
}

/// Perpendicular distance in metres from point `p` to the segment AB,
/// using an equirectangular projection centred on the segment midpoint.
private func perpendicularDistanceMeters(
    _ p: CLLocationCoordinate2D,
    from a: CLLocationCoordinate2D,
    to b: CLLocationCoordinate2D
) -> Double {
    let R = 6_371_000.0
    let midLat = ((a.latitude + b.latitude) / 2) * .pi / 180
    let cosLat = cos(midLat)

    func xy(_ c: CLLocationCoordinate2D) -> (Double, Double) {
        (c.longitude * .pi / 180 * cosLat * R,
         c.latitude  * .pi / 180 * R)
    }
    let (ax, ay) = xy(a)
    let (bx, by) = xy(b)
    let (px, py) = xy(p)

    let dx = bx - ax, dy = by - ay
    let len2 = dx*dx + dy*dy
    guard len2 > 0 else {
        let ex = px - ax, ey = py - ay
        return sqrt(ex*ex + ey*ey)
    }
    let t  = max(0, min(1, ((px - ax)*dx + (py - ay)*dy) / len2))
    let cx = px - (ax + t*dx)
    let cy = py - (ay + t*dy)
    return sqrt(cx*cx + cy*cy)
}

// MARK: - Route convenience

extension Route {
    /// Definition-point coordinates simplified by RDP at the given epsilon (metres).
    /// Pass epsilon ≤ 0 to get raw coordinates unchanged.
    func smoothedCoordinates(epsilon: Double) -> [CLLocationCoordinate2D] {
        let raw = sortedDefinitionPoints.map(\.coordinate)
        guard epsilon > 0 else { return raw }
        return rdpSmooth(raw, epsilon: epsilon)
    }
}
