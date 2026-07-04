//
//  PresetEditorView.swift
//  surge15
//

import SwiftUI

// MARK: - Shared editor

struct PresetEditorView: View {
    let title: String
    @Binding var presets: [Double]
    let format: (Double) -> String
    let defaults: [Double]
    let validate: (String) -> Double?
    var defaultValue: Binding<Double>? = nil

    @State private var addText = ""
    @State private var showAddError = false

    private var sorted: [Double] { presets.sorted() }

    var body: some View {
        List {
            if let defaultBinding = defaultValue {
                Section("Default") {
                    Picker("Default", selection: defaultBinding) {
                        ForEach(sorted, id: \.self) { value in
                            Text(format(value)).tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section {
                ForEach(sorted, id: \.self) { value in
                    Text(format(value))
                }
                .onDelete { indices in
                    guard presets.count > 1 else { return }
                    let toRemove = Set(indices.map { sorted[$0] })
                    presets.removeAll { toRemove.contains($0) }
                }
            } header: {
                Text("Current Presets")
            } footer: {
                if presets.count <= 1 {
                    Text("At least one preset is required.")
                }
            }

            Section {
                HStack {
                    TextField("Enter value", text: $addText)
                        .keyboardType(.numbersAndPunctuation)
                    Button("Add") {
                        if let value = validate(addText), !presets.contains(value) {
                            presets.append(value)
                            addText = ""
                        } else {
                            showAddError = true
                        }
                    }
                    .disabled(addText.isEmpty)
                }
            } header: {
                Text("Add Preset")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Reset") { presets = defaults }
            }
        }
        .alert("Invalid Value", isPresented: $showAddError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enter a valid number not already in the list.")
        }
    }
}

// MARK: - Lap presets editor

struct LapPresetsEditorView: View {
    @AppStorage(lapPresetsKey)  private var storage     = JSONStringArray<Int>(defaultLapPresets)
    @AppStorage(targetLapsKey)  private var defaultLaps: Int = defaultLapPresets.first ?? 1

    var body: some View {
        PresetEditorView(
            title: "Lap Presets",
            presets: Binding(
                get: { storage.values.map(Double.init) },
                set: { storage.values = $0.map { Int($0) } }
            ),
            format: { "\(Int($0))" },
            defaults: defaultLapPresets.map(Double.init),
            validate: { str in
                guard let n = Int(str), n >= 1 else { return nil }
                return Double(n)
            },
            defaultValue: Binding(
                get: { Double(defaultLaps) },
                set: { defaultLaps = Int($0) }
            )
        )
    }
}

// MARK: - Pace presets editor (seconds/km, displayed as m:ss)

struct PacePresetsEditorView: View {
    @AppStorage(pacePresetsKey)  private var storage      = JSONStringArray<Double>(defaultPacePresets)
    @AppStorage(targetPaceKey)   private var defaultPace: Double = defaultPacePresets.first ?? 210

    var body: some View {
        PresetEditorView(
            title: "Pace Presets",
            presets: Binding(get: { storage.values }, set: { storage.values = $0 }),
            format: { Formatters.pace(secondsPerKilometer: $0) },
            defaults: defaultPacePresets,
            validate: { str in
                guard let n = Double(str), n >= 1 else { return nil }
                return n
            },
            defaultValue: Binding(
                get: { defaultPace },
                set: { defaultPace = $0 }
            )
        )
    }
}

// MARK: - Duration presets editor (seconds, displayed as m:ss)

struct DurationPresetsEditorView: View {
    @AppStorage(durationPresetsKey)  private var storage         = JSONStringArray<Double>(defaultDurationPresets)
    @AppStorage(targetDurationKey)   private var defaultDuration: Double = defaultDurationPresets.first ?? 30

    var body: some View {
        PresetEditorView(
            title: "Duration Presets",
            presets: Binding(get: { storage.values }, set: { storage.values = $0 }),
            format: { Formatters.duration($0) },
            defaults: defaultDurationPresets,
            validate: { str in
                guard let n = Double(str), n >= 1 else { return nil }
                return n
            },
            defaultValue: Binding(
                get: { defaultDuration },
                set: { defaultDuration = $0 }
            )
        )
    }
}

// MARK: - Rep presets editor

struct RepPresetsEditorView: View {
    @AppStorage(repPresetsKey)  private var storage     = JSONStringArray<Double>(defaultRepPresets)
    @AppStorage(targetRepsKey)  private var defaultReps: Double = defaultRepPresets.first ?? 10

    var body: some View {
        PresetEditorView(
            title: "Rep Presets",
            presets: Binding(get: { storage.values }, set: { storage.values = $0 }),
            format: { "\(Int($0))" },
            defaults: defaultRepPresets,
            validate: { str in
                guard let n = Int(str), n >= 1 else { return nil }
                return Double(n)
            },
            defaultValue: Binding(
                get: { defaultReps },
                set: { defaultReps = $0 }
            )
        )
    }
}

// MARK: - Minute presets editor

struct MinutePresetsEditorView: View {
    @AppStorage(minutePresetsKey)  private var storage        = JSONStringArray<Double>(defaultMinutePresets)
    @AppStorage(targetMinutesKey)  private var defaultMinutes: Double = defaultMinutePresets.first ?? 0.5

    private func formatMinutes(_ value: Double) -> String {
        value < 1 ? "\(Int(value * 60))s" : "\(Int(value))min"
    }

    var body: some View {
        PresetEditorView(
            title: "Minute Presets",
            presets: Binding(get: { storage.values }, set: { storage.values = $0 }),
            format: formatMinutes,
            defaults: defaultMinutePresets,
            validate: { str in
                guard let n = Double(str), n >= 0.5 else { return nil }
                return n
            },
            defaultValue: Binding(
                get: { defaultMinutes },
                set: { defaultMinutes = $0 }
            )
        )
    }
}

// MARK: - Distance presets editor

struct MeterPresetsEditorView: View {
    @AppStorage(meterPresetsKey)  private var storage      = JSONStringArray<Double>(defaultMeterPresets)
    @AppStorage(targetMetersKey)  private var defaultMeters: Double = defaultMeterPresets.first ?? 1

    var body: some View {
        PresetEditorView(
            title: "Distance Presets",
            presets: Binding(
                get: { storage.values },
                set: { storage.values = $0 }
            ),
            format: { Formatters.distance($0) },
            defaults: defaultMeterPresets,
            validate: { str in
                guard let n = Double(str), n >= 1 else { return nil }
                return n
            },
            defaultValue: Binding(
                get: { defaultMeters },
                set: { defaultMeters = $0 }
            )
        )
    }
}
