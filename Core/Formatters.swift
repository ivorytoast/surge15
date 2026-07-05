//
//  Formatters.swift
//  surge15
//

import Foundation

enum Formatters {
    static func distance(_ meters: Double) -> String {
        if meters < 1000 {
            return String(format: "%.0f m", meters)
        }
        return String(format: "%.2f km", meters / 1000)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds.rounded())
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    /// Pace formatted as min:sec / km, e.g. "5:32 /km".
    static func pace(secondsPerKilometer: Double) -> String {
        let totalSeconds = Int(secondsPerKilometer.rounded())
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d /km", m, s)
    }
}
