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

struct SettingsHomeView: View {
    @AppStorage(countdownDefaultKey) private var countdownDefault: Int = countdownDefaultValue
    @AppStorage(autoRestDurationKey) private var autoRestDuration: Int = autoRestDurationDefault
    @Environment(\.modelContext) private var modelContext

    @State private var showingImportRoute = false
    @State private var importCode: String = ""
    @State private var isImporting = false
    @State private var importError: String? = nil

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

                Section("Sharing") {
                    Button {
                        importCode = ""
                        showingImportRoute = true
                    } label: {
                        Label("Import Route", systemImage: "arrow.down.circle")
                            .foregroundStyle(.primary)
                    }
                }

                Section("Help") {
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
