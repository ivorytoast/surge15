//
//  SurgeSessionPickerSheet.swift
//  surge15
//
//  Shown when the user taps "Start Session" on a Route. The user must pick
//  (or create) a SurgeSession from today before recording can start.
//

import SwiftUI
import SwiftData

struct SurgeSessionPickerSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SurgeSession.createdAt, order: .reverse) private var allSurgeSessions: [SurgeSession]

    let onSelect: (SurgeSession) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        createAndSelectNew()
                    } label: {
                        Label("New Surge Session", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                if todaysSurgeSessions.isEmpty {
                    Section {
                        Text("No surge sessions yet today. Tap **New Surge Session** to start one.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Today") {
                        ForEach(todaysSurgeSessions) { surge in
                            Button {
                                onSelect(surge)
                            } label: {
                                row(surge)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Pick Surge Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var todaysSurgeSessions: [SurgeSession] {
        let now = Date()
        return allSurgeSessions.filter {
            Calendar.current.isDate($0.date, inSameDayAs: now)
        }
    }

    private func row(_ surge: SurgeSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(surge.name).font(.headline)
                HStack(spacing: 8) {
                    Text(surge.createdAt.formatted(date: .omitted, time: .shortened))
                    Text("·")
                    Text("\(surge.sessions.count) session\(surge.sessions.count == 1 ? "" : "s")")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func createAndSelectNew() {
        let now = Date()
        let surge = SurgeSession(
            name: SurgeSession.autoName(for: now),
            date: Calendar.current.startOfDay(for: now),
            createdAt: now
        )
        modelContext.insert(surge)
        onSelect(surge)
    }
}

#Preview {
    Color.gray
        .sheet(isPresented: .constant(true)) {
            SurgeSessionPickerSheet(onSelect: { _ in })
        }
        .modelContainer(for: SurgeSession.self, inMemory: true)
}
