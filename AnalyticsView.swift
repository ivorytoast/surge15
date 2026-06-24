//
//  AnalyticsView.swift
//  surge15
//

import SwiftUI
import Charts
import SwiftData

// MARK: - Range

enum AnalyticsRange: String, CaseIterable {
    case sevenDays  = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "3M"
    case allTime    = "All"

    var cutoffDate: Date {
        let cal = Calendar.current
        switch self {
        case .sevenDays:  return cal.date(byAdding: .day, value: -7,  to: .now) ?? .now
        case .thirtyDays: return cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        case .ninetyDays: return cal.date(byAdding: .day, value: -90, to: .now) ?? .now
        case .allTime:    return .distantPast
        }
    }

    var groupByWeek: Bool { self == .ninetyDays || self == .allTime }
}

// MARK: - Main view

struct AnalyticsView: View {
    @Query(sort: \SurgeSession.date) private var allSessions: [SurgeSession]
    @State private var range: AnalyticsRange = .thirtyDays
    @State private var selectedFrequencyDate: Date? = nil
    @State private var selectedPaceDate: Date? = nil

    var body: some View {
        if filteredSessions.isEmpty {
            ContentUnavailableView {
                Label("No Workouts Yet", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Start logging workouts to see your trends here.")
            }
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    rangePickerRow
                        .padding(.horizontal)

                    frequencyCard

                    if !pacePoints.isEmpty {
                        paceCard
                    }

                    if !planStats.isEmpty {
                        planHistoryCard
                    }
                }
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Filtered sessions

    private var filteredSessions: [SurgeSession] {
        allSessions.filter { $0.date >= range.cutoffDate }
    }

    // MARK: - Workout frequency data

    private struct WorkoutDay: Identifiable {
        let date: Date
        let count: Int
        var id: Date { date }
    }

    private var workoutDays: [WorkoutDay] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { surge -> Date in
            if range.groupByWeek {
                return cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: surge.date)) ?? surge.date
            }
            return cal.startOfDay(for: surge.date)
        }
        return grouped.map { WorkoutDay(date: $0.key, count: $0.value.count) }
            .sorted { $0.date < $1.date }
    }

    private var selectedWorkoutDay: WorkoutDay? {
        guard let sel = selectedFrequencyDate else { return nil }
        return workoutDays.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) })
    }

    // MARK: - Frequency card

    private var frequencyCard: some View {
        cardShell {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedWorkoutDay.map { "\($0.count)" } ?? "\(filteredSessions.count)")
                        .font(.system(.title, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.15), value: selectedWorkoutDay?.id)
                    Text(frequencySubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            workoutFrequencyChart
        }
    }

    private var frequencySubtitle: String {
        if let day = selectedWorkoutDay {
            let fmt: Date.FormatStyle = range.groupByWeek
                ? .dateTime.month(.abbreviated).day()
                : .dateTime.weekday(.wide).month(.abbreviated).day()
            return day.date.formatted(fmt)
        }
        return range.groupByWeek ? "workouts (by week)" : "total workouts"
    }

    @ViewBuilder
    private var workoutFrequencyChart: some View {
        let unit: Calendar.Component = range.groupByWeek ? .weekOfYear : .day
        let hasSelection = selectedWorkoutDay != nil

        Chart {
            ForEach(workoutDays) { day in
                let isSelected = selectedWorkoutDay?.id == day.id
                BarMark(
                    x: .value("Date", day.date, unit: unit),
                    y: .value("Workouts", day.count)
                )
                .foregroundStyle(
                    hasSelection && !isSelected
                        ? AnyShapeStyle(Color.blue.opacity(0.2))
                        : AnyShapeStyle(Color.blue.gradient)
                )
                .cornerRadius(5)
            }

            if let sel = selectedWorkoutDay {
                RuleMark(x: .value("Selected", sel.date, unit: unit))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .zIndex(-1)
            }
        }
        .chartXSelection(value: $selectedFrequencyDate)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xDesiredCount)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel {
                        Text(d.formatted(xLabelFormat))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .frame(height: 170)
    }

    // MARK: - Run pace data

    private struct PacePoint: Identifiable {
        let date: Date
        let paceSecondsPerKm: Double
        var id: String { "\(date.timeIntervalSince1970)" }
    }

    private var pacePoints: [PacePoint] {
        filteredSessions.flatMap { surge in
            surge.sessions.compactMap { session -> PacePoint? in
                guard session.workoutType == .run,
                      let pace = session.paceSecondsPerKilometer,
                      pace > 60, pace < 1800
                else { return nil }
                return PacePoint(date: session.startedAt, paceSecondsPerKm: pace)
            }
        }
        .sorted { $0.date < $1.date }
    }

    private var selectedPacePoint: PacePoint? {
        guard let sel = selectedPaceDate else { return nil }
        return pacePoints.min(by: { abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel)) })
    }

    private var avgPaceSeconds: Double? {
        guard !pacePoints.isEmpty else { return nil }
        return pacePoints.map(\.paceSecondsPerKm).reduce(0, +) / Double(pacePoints.count)
    }

    private var bestPaceSeconds: Double? {
        pacePoints.map(\.paceSecondsPerKm).min()
    }

    // MARK: - Pace card

    private var paceCard: some View {
        cardShell {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    if let sel = selectedPacePoint {
                        Text(Formatters.pace(secondsPerKilometer: sel.paceSecondsPerKm))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .contentTransition(.numericText())
                        Text(sel.date.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if let avg = avgPaceSeconds {
                        Text(Formatters.pace(secondsPerKilometer: avg))
                            .font(.system(.title, design: .rounded).weight(.bold))
                        Text("avg pace · min/km")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let best = bestPaceSeconds, selectedPacePoint == nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Formatters.pace(secondsPerKilometer: best))
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.green)
                        Text("best")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            runPaceChart
        }
    }

    @ViewBuilder
    private var runPaceChart: some View {
        let paces = pacePoints.map(\.paceSecondsPerKm)
        let minP  = paces.min() ?? 180
        let maxP  = paces.max() ?? 600
        let pad   = max(30, (maxP - minP) * 0.3)

        Chart {
            ForEach(pacePoints) { pt in
                LineMark(
                    x: .value("Date", pt.date),
                    y: .value("Pace", pt.paceSecondsPerKm)
                )
                .foregroundStyle(Color.green.opacity(0.8))
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Date", pt.date),
                    y: .value("Pace", pt.paceSecondsPerKm)
                )
                .foregroundStyle(selectedPacePoint?.id == pt.id ? Color.green : Color.green.opacity(0.5))
                .symbolSize(selectedPacePoint?.id == pt.id ? 80 : 36)
            }

            if let sel = selectedPacePoint {
                RuleMark(x: .value("Selected", sel.date))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .zIndex(-1)
            }
        }
        .chartXSelection(value: $selectedPaceDate)
        .chartYScale(domain: max(0, minP - pad)...(maxP + pad))
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisGridLine()
                if let v = value.as(Double.self) {
                    AxisValueLabel {
                        Text(Formatters.pace(secondsPerKilometer: v))
                            .font(.caption2)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: xDesiredCount)) { value in
                if let d = value.as(Date.self) {
                    AxisValueLabel {
                        Text(d.formatted(xLabelFormat))
                            .font(.caption2)
                    }
                }
            }
        }
        .frame(height: 170)
    }

    // MARK: - Plan history

    private struct PlanStat: Identifiable {
        let plan: Plan
        let runCount: Int
        let bestDuration: TimeInterval?
        let avgDuration: TimeInterval?
        let lastDate: Date?
        var id: PersistentIdentifier { plan.persistentModelID }
    }

    private var planStats: [PlanStat] {
        let withPlan = filteredSessions.filter { $0.plan != nil }
        let grouped  = Dictionary(grouping: withPlan) { $0.plan! }
        return grouped.map { plan, sessions in
            let durations = sessions.compactMap(\.totalDurationSeconds)
            return PlanStat(
                plan: plan,
                runCount: sessions.count,
                bestDuration: durations.min(),
                avgDuration: durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count),
                lastDate: sessions.map(\.date).max()
            )
        }
        .sorted { ($0.lastDate ?? .distantPast) > ($1.lastDate ?? .distantPast) }
    }

    @ViewBuilder
    private var planHistoryCard: some View {
        cardShell {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan History")
                    .font(.headline)
                Text("Each time you ran a plan")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(planStats.enumerated()), id: \.element.id) { idx, stat in
                if idx > 0 { Divider() }
                VStack(alignment: .leading, spacing: 8) {
                    Text(stat.plan.name)
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 0) {
                        miniStat(value: "\(stat.runCount)", label: "runs")
                        if let best = stat.bestDuration {
                            miniStat(value: Formatters.duration(best), label: "best")
                        }
                        if let avg = stat.avgDuration {
                            miniStat(value: Formatters.duration(avg), label: "avg")
                        }
                        if let last = stat.lastDate {
                            miniStat(
                                value: last.formatted(.dateTime.month(.abbreviated).day()),
                                label: "last run"
                            )
                        }
                    }
                }
            }
        }
    }

    private func miniStat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Range picker

    private var rangePickerRow: some View {
        HStack(spacing: 8) {
            ForEach(AnalyticsRange.allCases, id: \.self) { r in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        range = r
                        selectedFrequencyDate = nil
                        selectedPaceDate = nil
                    }
                } label: {
                    Text(r.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            range == r ? Color.blue : Color(.secondarySystemBackground),
                            in: Capsule()
                        )
                        .foregroundStyle(range == r ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - X-axis helpers

    private var xDesiredCount: Int {
        switch range {
        case .sevenDays:  return 7
        case .thirtyDays: return 5
        case .ninetyDays: return 4
        case .allTime:    return 4
        }
    }

    private var xLabelFormat: Date.FormatStyle {
        switch range {
        case .sevenDays:            return .dateTime.weekday(.abbreviated)
        case .thirtyDays:           return .dateTime.month(.abbreviated).day()
        case .ninetyDays, .allTime: return .dateTime.month(.abbreviated)
        }
    }

    // MARK: - Card shell

    @ViewBuilder
    private func cardShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }
}
