//
//  ExerciseRecordingView.swift
//  surge15
//
//  Timer-based recording screen for non-GPS exercises (Lunge, Burpee Broad Jump).
//  User picks measure + target before starting, then times the exercise live.
//

import SwiftUI
import SwiftData
import UIKit

struct ExerciseRecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let workoutType: WorkoutItemType
    var surgeSession: SurgeSession?

    @State private var measure: WorkoutMeasure
    @State private var targetValue: Double
    @State private var startedAt: Date?
    @State private var endedAt: Date?
    @State private var now = Date()
    @State private var hasSaved = false

    @State private var isCountingDown = false
    @State private var countdownRemaining = 5
    @State private var countdownTask: Task<Void, Never>?

    private let lapPresets: [Double]     = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15, 20, 25, 50]
    private let meterPresets: [Double]  = [1, 5, 10, 20, 24, 40, 50, 75, 80, 100,
                                           125, 150, 200, 250, 300, 400, 500, 1000]
    private let repPresets: [Double]    = [5, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100]
    private let minutePresets: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5, 7, 10, 15, 20]

    init(workoutType: WorkoutItemType, surgeSession: SurgeSession? = nil) {
        self.workoutType = workoutType
        self.surgeSession = surgeSession
        let defaultMeasure = workoutType.availableMeasures[0]
        _measure = State(initialValue: defaultMeasure)
        let defaultTarget: Double = {
            switch workoutType {
            case .run:  return 400
            case .row:  return 1000
            case .rest: return 2
            default:    return defaultMeasure == .meters || defaultMeasure == .yards ? 24 : 10
            }
        }()
        _targetValue = State(initialValue: defaultTarget)
    }

    private var isActive: Bool { startedAt != nil && endedAt == nil && !isCountingDown }
    private var elapsed: TimeInterval { startedAt.map { now.timeIntervalSince($0) } ?? 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                if hasSaved {
                    completedBlock
                } else if isActive {
                    activeBlock
                } else {
                    gateBlock
                }

                if isCountingDown {
                    countdownOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isCountingDown)
            .animation(.easeInOut(duration: 0.3), value: hasSaved)
            .navigationTitle(workoutType.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isActive && !hasSaved && !isCountingDown {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onDisappear { countdownTask?.cancel() }
    }

    // MARK: - Gate (pre-start)

    private var gateBlock: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: workoutType.systemImage)
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
                Text(workoutType.displayName)
                    .font(.title.bold())
            }

            VStack(spacing: 16) {
                if workoutType.availableMeasures.count > 1 {
                    Picker("Measure", selection: $measure) {
                        ForEach(workoutType.availableMeasures, id: \.self) { m in
                            Text(m.displayName).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: measure) { _, _ in
                        switch measure {
                        case .meters, .yards: targetValue = 24
                        case .laps:           targetValue = 1
                        case .reps:           targetValue = 10
                        case .minutes:        targetValue = 2
                        }
                    }
                }

                chipScrollRow
            }
            .padding(20)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal)

            Spacer()

            Button { startCountdown() } label: {
                Text("Start")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Active (recording)

    private var activeBlock: some View {
        VStack(spacing: 24) {
            Spacer()

            HStack(spacing: 10) {
                Image(systemName: workoutType.systemImage)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(measure.formatted(targetValue))
                    .font(.title2.bold())
            }

            VStack(spacing: 4) {
                Text(Formatters.duration(elapsed))
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("elapsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                endedAt = Date()
                save()
            } label: {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    // MARK: - Completed

    private var completedBlock: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text(workoutType.displayName)
                .font(.title.bold())

            HStack(spacing: 32) {
                statCell(value: measure.formatted(targetValue), label: measure.displayName.lowercased())
                if let end = endedAt, let start = startedAt {
                    statCell(value: Formatters.duration(end.timeIntervalSince(start)), label: "time")
                }
            }

            Spacer()

            Button { dismiss() } label: {
                Text("Back to Workout")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Chip scroll

    private var chipScrollRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(currentPresets, id: \.self) { preset in
                    chip(preset)
                }
            }
            .padding(.vertical, 4)
            .padding(.leading, 2)
        }
        .mask(
            HStack(spacing: 0) {
                Rectangle()
                LinearGradient(colors: [.white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 40)
            }
        )
    }

    private func chip(_ value: Double) -> some View {
        let selected = value == targetValue
        let label: String = {
            switch measure {
            case .meters:  return value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value))m"
            case .yards:   return "\(Int(value))yd"
            case .laps:    return "\(Int(value))"
            case .reps:    return "\(Int(value))"
            case .minutes: return value < 1 ? "\(Int(value * 60))s" : "\(Int(value))m"
            }
        }()
        return Button { targetValue = value } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.blue : Color(.secondarySystemFill), in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var currentPresets: [Double] {
        switch measure {
        case .laps:           return lapPresets
        case .meters, .yards: return meterPresets
        case .reps:           return repPresets
        case .minutes:        return minutePresets
        }
    }

    // MARK: - Countdown

    private var countdownOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 32) {
                Text("\(countdownRemaining)")
                    .font(.system(size: 120, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text("Get Ready")
                    .font(.title2.bold())
                    .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: 32) {
                    Button {
                        if countdownRemaining > 1 {
                            countdownRemaining -= 1
                        } else {
                            countdownTask?.cancel()
                            isCountingDown = false
                            startedAt = Date()
                        }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    Button {
                        countdownRemaining += 1
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Button("Cancel") {
                    countdownTask?.cancel()
                    withAnimation { isCountingDown = false }
                }
                .foregroundStyle(.white.opacity(0.6))
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Logic

    private func startCountdown() {
        countdownRemaining = 5
        withAnimation { isCountingDown = true }
        countdownTask = Task { @MainActor in
            while countdownRemaining > 0 && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                if countdownRemaining > 0 {
                    withAnimation { countdownRemaining -= 1 }
                    UIImpactFeedbackGenerator(style: countdownRemaining == 0 ? .heavy : .medium).impactOccurred()
                }
            }
            guard !Task.isCancelled else { isCountingDown = false; return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation { isCountingDown = false }
            startedAt = Date()
        }
    }

    private func save() {
        guard let start = startedAt else { return }
        let session = Session(startedAt: start)
        session.workoutType = workoutType
        session.workoutMeasure = measure
        session.targetValue = targetValue
        session.endedAt = endedAt ?? Date()
        modelContext.insert(session)
        if let surge = surgeSession {
            session.surgeSession = surge
            surge.sessions.append(session)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        hasSaved = true
    }
}
