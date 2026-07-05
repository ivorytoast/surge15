//
//  SettingsHomeView.swift
//  surge15
//

import SwiftUI
import SwiftData

let countdownDefaultKey = "countdownDefault"
let countdownDefaultValue: Int = 5
let autoRestDurationKey = "autoRestDuration"
let autoRestDurationDefault: Int = 30
let hiddenBuiltinExercisesKey = "hiddenBuiltinExercises"

private enum SettingsHelp: Identifiable {
    case countdown, autoRest
    case routes, groups, exercises, presets
    case importRoute

    var id: Self { self }

    var title: String {
        switch self {
        case .countdown:  "Countdown"
        case .autoRest:   "Rest Duration"
        case .routes:     "Routes"
        case .groups:     "Groups"
        case .exercises:  "Exercises"
        case .presets:    "Presets"
        case .importRoute:"Import Route"
        }
    }

    var detail: String {
        switch self {
        case .countdown:
            "The seconds shown on the countdown timer before a GPS run or exercise begins — giving you time to get into position."
        case .autoRest:
            "The length of the automatic rest break inserted between exercises in Auto mode. Tap 'Start Now' on the timer to skip it early."
        case .routes:
            "View and manage your saved GPS routes. You can rename or permanently delete any route."
        case .groups:
            "Organize your plans into groups. Rename a group, change its color, add or remove plans, or delete the group without losing its plans."
        case .exercises:
            "Show or hide built-in exercises, and create custom exercises that appear in the exercise picker during workouts."
        case .presets:
            "Customize the quick-select chips shown when starting exercises and runs — lap counts, distances, reps, minutes, pace targets, and durations."
        case .importRoute:
            "Import a GPS route shared by another surge15 user. Ask them for the 8-character share code and enter it here."
        }
    }
}

struct SettingsHomeView: View {
    @AppStorage(countdownDefaultKey) private var countdownDefault: Int = countdownDefaultValue
    @AppStorage(autoRestDurationKey) private var autoRestDuration: Int = autoRestDurationDefault
    @Environment(\.modelContext) private var modelContext

    @State private var showingImportRoute = false
    @State private var importCode: String = ""
    @State private var isImporting = false
    @State private var importError: String? = nil
    @State private var activeHelp: SettingsHelp? = nil

    var body: some View {
        NavigationStack {
            List {
                Section("Timers") {
                    HStack(spacing: 12) {
                        infoButton(.countdown)
                        Stepper(value: $countdownDefault, in: 3...30) {
                            HStack {
                                Text("Countdown")
                                Spacer()
                                Text("\(countdownDefault) sec")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    HStack(spacing: 12) {
                        infoButton(.autoRest)
                        Stepper(value: $autoRestDuration, in: 5...120, step: 5) {
                            HStack {
                                Text("Rest Duration")
                                Spacer()
                                Text(Self.formatRestDuration(autoRestDuration))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }

                Section("Workouts") {
                    HStack(spacing: 12) {
                        infoButton(.routes)
                        NavigationLink {
                            RouteLibraryView()
                        } label: {
                            Label("Routes", systemImage: "map")
                        }
                    }
                    HStack(spacing: 12) {
                        infoButton(.groups)
                        NavigationLink {
                            GroupLibraryView()
                        } label: {
                            Label("Groups", systemImage: "folder")
                        }
                    }
                    HStack(spacing: 12) {
                        infoButton(.exercises)
                        NavigationLink {
                            ExerciseLibraryView()
                        } label: {
                            Label("Exercises", systemImage: "dumbbell.fill")
                        }
                    }
                    HStack(spacing: 12) {
                        infoButton(.presets)
                        NavigationLink {
                            PresetListView()
                        } label: {
                            Label("Presets", systemImage: "dial.low")
                        }
                    }
                }

                Section("Sharing") {
                    HStack(spacing: 12) {
                        infoButton(.importRoute)
                        Button {
                            importCode = ""
                            showingImportRoute = true
                        } label: {
                            Label("Import Route", systemImage: "arrow.down.circle")
                                .foregroundStyle(.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("App") {
                    Link(destination: URL(string: "https://surge15.app/")!) {
                        Label("surge15.app", systemImage: "globe")
                    }
                }

            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingImportRoute) {
                importRouteSheet
            }
            .alert(activeHelp?.title ?? "", isPresented: Binding(
                get: { activeHelp != nil },
                set: { if !$0 { activeHelp = nil } }
            )) {
                Button("OK", role: .cancel) { activeHelp = nil }
            } message: {
                if let h = activeHelp { Text(h.detail) }
            }
        }
    }

    private var importRouteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. ABTDFYD3", text: $importCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .monospaced))
                } header: {
                    Text("Enter Share Code")
                } footer: {
                    Text("Ask the person sharing their route for the 8-character code.")
                }
            }
            .navigationTitle("Import Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingImportRoute = false }
                        .disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isImporting {
                        ProgressView()
                    } else {
                        Button("Import") {
                            isImporting = true
                            Task {
                                do {
                                    _ = try await RouteShareService.importRoute(
                                        code: importCode,
                                        into: modelContext
                                    )
                                    isImporting = false
                                    showingImportRoute = false
                                } catch {
                                    isImporting = false
                                    importError = (error as? RouteShareService.ShareError)?.errorDescription
                                        ?? "Something went wrong."
                                }
                            }
                        }
                        .disabled(importCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .alert("Import Failed", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            )) {
                Button("OK", role: .cancel) { importError = nil }
            } message: {
                Text(importError ?? "")
            }
        }
        .presentationDetents([.medium])
    }


    @ViewBuilder private func infoButton(_ help: SettingsHelp) -> some View {
        Button { activeHelp = help } label: {
            Image(systemName: "info.circle")
                .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
    }

    private static func formatRestDuration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds) sec" }
        let m = seconds / 60
        let s = seconds % 60
        return s == 0 ? "\(m) min" : "\(m):\(String(format: "%02d", s))"
    }
}

// MARK: - Preset sub-list

struct PresetListView: View {
    var body: some View {
        List {
            NavigationLink {
                LapPresetsEditorView()
            } label: {
                Label("Lap Presets", systemImage: "repeat")
            }
            NavigationLink {
                MeterPresetsEditorView()
            } label: {
                Label("Distance Presets", systemImage: "ruler")
            }
            NavigationLink {
                RepPresetsEditorView()
            } label: {
                Label("Rep Presets", systemImage: "number")
            }
            NavigationLink {
                MinutePresetsEditorView()
            } label: {
                Label("Minute Presets", systemImage: "timer")
            }
            NavigationLink {
                PacePresetsEditorView()
            } label: {
                Label("Pace Presets", systemImage: "speedometer")
            }
            NavigationLink {
                DurationPresetsEditorView()
            } label: {
                Label("Duration Presets", systemImage: "stopwatch")
            }
        }
        .navigationTitle("Presets")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsHomeView()
}
