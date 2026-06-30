//
//  SettingsHomeView.swift
//  surge15
//

import SwiftUI

let countdownDefaultKey = "countdownDefault"
let countdownDefaultValue: Int = 5
let autoRestDurationKey = "autoRestDuration"
let autoRestDurationDefault: Int = 30
let hiddenBuiltinExercisesKey = "hiddenBuiltinExercises"

struct SettingsHomeView: View {
    @AppStorage(countdownDefaultKey) private var countdownDefault: Int = countdownDefaultValue
    @AppStorage(autoRestDurationKey) private var autoRestDuration: Int = autoRestDurationDefault

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $countdownDefault, in: 3...30) {
                        HStack {
                            Text("Countdown")
                            Spacer()
                            Text("\(countdownDefault) sec")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Workout")
                } footer: {
                    Text("Seconds shown before GPS runs and exercises begin.")
                }

                Section {
                    Stepper(value: $autoRestDuration, in: 5...120, step: 5) {
                        HStack {
                            Text("Rest Duration")
                            Spacer()
                            Text(Self.formatRestDuration(autoRestDuration))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Auto Mode")
                } footer: {
                    Text("Rest time inserted between exercises in Auto mode. Tap 'Start Now' on the timer to skip it early.")
                }

                Section {
                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercises", systemImage: "dumbbell.fill")
                    }
                } header: {
                    Text("Library")
                } footer: {
                    Text("Add custom exercises, or hide built-ins you don't use.")
                }

                Section("Help") {
                    Link(destination: URL(string: "https://surge15.app/")!) {
                        Label("surge15.app", systemImage: "globe")
                    }
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private static func formatRestDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
    }
}

#Preview {
    SettingsHomeView()
}
