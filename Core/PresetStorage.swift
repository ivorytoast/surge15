//
//  PresetStorage.swift
//  surge15
//

import Foundation

// MARK: - Keys

let lapPresetsKey    = "lapPresets"
let meterPresetsKey  = "meterPresets"
let repPresetsKey      = "repPresets"
let minutePresetsKey   = "minutePresets"
let pacePresetsKey     = "pacePresets"
let durationPresetsKey = "durationPresets"
let targetLapsKey    = "targetLaps"
let targetMetersKey  = "targetMeters"
let targetRepsKey    = "targetReps"
let targetMinutesKey = "targetMinutes"
let targetPaceKey     = "targetPace"
let targetDurationKey = "targetDuration"

// MARK: - Defaults

let defaultLapPresets: [Int] = [
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 15, 20, 25, 50, 100
]

let defaultMeterPresets: [Double] = [
    1, 5, 10, 20, 40, 50, 75, 100, 125, 150, 200, 250,
    300, 350, 400, 450, 500, 550, 600, 650, 700, 750,
    800, 850, 900, 950, 1000
]

let defaultRepPresets: [Double]      = [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100]
let defaultMinutePresets: [Double]   = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 7, 10, 15, 20]
let defaultPacePresets: [Double]     = [210, 240, 270, 300, 330, 360, 390, 420, 480, 600]
let defaultDurationPresets: [Double] = [30, 45, 60, 90, 120, 150, 180, 240, 300, 420, 600]

// MARK: - AppStorage-compatible JSON array wrapper

struct JSONStringArray<T: Codable>: RawRepresentable {
    var values: [T]

    init(_ values: [T]) { self.values = values }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([T].self, from: data)
        else { return nil }
        values = decoded
    }

    var rawValue: String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8)
        else { return "[]" }
        return string
    }
}
