//
//  SettingsHomeView.swift
//  surge15
//

import SwiftUI

let countdownDefaultKey = "countdownDefault"
let countdownDefaultValue: Int = 5

struct SettingsHomeView: View {
    @AppStorage(countdownDefaultKey) private var countdownDefault: Int = countdownDefaultValue

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

                Section("Developer") {
                    NavigationLink {
                        RouteDebugView()
                    } label: {
                        Label("Route Smoothing Debug", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    SettingsHomeView()
}
