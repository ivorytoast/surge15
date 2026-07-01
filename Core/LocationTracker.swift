//
//  LocationTracker.swift
//  surge15
//

import Foundation
import CoreLocation
import Observation

@Observable
final class LocationTracker: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var pendingSingleLocation = false

    var isRecording = false
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var recordedLocations: [CLLocation] = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        authorizationStatus = manager.authorizationStatus
    }

    func requestAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func start() {
        recordedLocations.removeAll()
        requestAuthorization()
        manager.startUpdatingLocation()
        isRecording = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        isRecording = false
    }

    /// Requests a one-shot location fix. Lightweight compared to start() — use this
    /// for things like the home-screen map where we only need to center on the user
    /// once without continuous updates.
    func requestSingleLocation() {
        switch authorizationStatus {
        case .notDetermined:
            pendingSingleLocation = true
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        recordedLocations.append(contentsOf: locations)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if pendingSingleLocation,
           authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            pendingSingleLocation = false
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Best-effort: keep recording state, surface error via console for now.
        print("Location error: \(error.localizedDescription)")
    }
}
