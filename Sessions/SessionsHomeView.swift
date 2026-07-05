//
//  SessionsHomeView.swift
//  surge15
//

import SwiftUI
import SwiftData

// MARK: - Sessions tab (calendar + surge sessions)

struct SessionsHomeView: View {
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            CalendarHomeView()
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: SurgeSession.self) { surge in
                    SurgeSessionDetailView(surgeSession: surge)
                }
        }
    }
}

struct CalendarHomeView: View {
    @Query(sort: \SurgeSession.date, order: .reverse) private var surgeSessions: [SurgeSession]
    @State private var selectedDate: Date = Date()

    var body: some View {
        VStack(spacing: 0) {
            CalendarMonthView(selectedDate: $selectedDate, activeDates: activeDates)
                .padding(.horizontal)
                .padding(.top, 12)

            Divider()
                .padding(.top, 8)

            if sessionsOnSelectedDate.isEmpty {
                emptyDayView
            } else {
                List {
                    ForEach(sessionsOnSelectedDate.sorted { $0.createdAt < $1.createdAt }) { surge in
                        NavigationLink(value: surge) {
                            surgeRow(surge)
                        }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var emptyDayView: some View {
        VStack {
            Spacer()
            Text(quoteForSelectedDate)
                .font(.title3.italic())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var isFuture: Bool {
        Calendar.current.startOfDay(for: selectedDate) > Calendar.current.startOfDay(for: Date())
    }

    /// Today with no sessions → motivating nudge. Future day → playful forward-look. Past empty day → roast.
    private var quoteForSelectedDate: String {
        let day = Int(Calendar.current.startOfDay(for: selectedDate).timeIntervalSince1970) / 86_400
        if isToday {
            return Quotes.calendarToday[abs(day) % Quotes.calendarToday.count]
        }
        if isFuture {
            return Quotes.calendarFutureDay[abs(day) % Quotes.calendarFutureDay.count]
        }
        return Quotes.calendarRestDay[abs(day) % Quotes.calendarRestDay.count]
    }

    private var activeDates: Set<Date> {
        Set(surgeSessions.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var sessionsOnSelectedDate: [SurgeSession] {
        surgeSessions.filter {
            Calendar.current.isDate($0.date, inSameDayAs: selectedDate)
        }
    }

    private func surgeRow(_ surge: SurgeSession) -> some View {
        HStack(alignment: .center, spacing: 16) {
            // Left: start time + total elapsed
            VStack(alignment: .leading, spacing: 3) {
                Text(surge.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text(surge.totalDurationSeconds.map { Formatters.duration($0) } ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 88, alignment: .leading)

            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1, height: 44)

            // Right: one bubble per session in order, or a funny quote if empty
            if surge.sortedSessions.isEmpty {
                let seed = Int(surge.createdAt.timeIntervalSince1970)
                Text(Quotes.calendarEmptySession[abs(seed) % Quotes.calendarEmptySession.count])
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
            } else {
                HStack(spacing: 6) {
                    ForEach(surge.sortedSessions) { session in
                        ZStack {
                            Circle()
                                .fill(Color(.tertiarySystemFill))
                                .frame(width: 36, height: 36)
                            Image(systemName: (session.workoutType ?? .run).systemImage)
                                .font(.system(size: 15))
                                .foregroundStyle(.primary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

// MARK: - Custom month-grid calendar with active-day dots

struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    let activeDates: Set<Date>

    @State private var displayedMonth: Date

    private let calendar: Calendar = .current

    init(selectedDate: Binding<Date>, activeDates: Set<Date>) {
        self._selectedDate = selectedDate
        self.activeDates = activeDates
        let start = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: selectedDate.wrappedValue)
        ) ?? selectedDate.wrappedValue
        self._displayedMonth = State(initialValue: start)
    }

    var body: some View {
        VStack(spacing: 10) {
            monthHeader
            weekdayHeader
            daysGrid
        }
    }

    private var monthHeader: some View {
        HStack {
            Text(displayedMonth.formatted(.dateTime.month(.wide).year()))
                .font(.title3.bold())
            Spacer()
            Button {
                changeMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            Button {
                changeMonth(1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { sym in
                Text(sym)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? Locale.current
        let symbols = formatter.veryShortWeekdaySymbols ?? formatter.shortWeekdaySymbols ?? []
        let first = calendar.firstWeekday - 1
        guard symbols.count == 7 else { return symbols }
        return Array(symbols[first...]) + Array(symbols[..<first])
    }

    private var daysGrid: some View {
        let cells = monthDayCells()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                if let date = cell {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let hasSession = activeDates.contains(calendar.startOfDay(for: date))
        let dayNumber = calendar.component(.day, from: date)

        return VStack(spacing: 3) {
            Text("\(dayNumber)")
                .font(.callout)
                .fontWeight(isSelected || isToday ? .semibold : .regular)
                .foregroundStyle(numberForeground(isSelected: isSelected, isToday: isToday))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(isSelected ? Color.accentColor : .clear)
                )
            Circle()
                .fill(hasSession ? Color.green : Color.clear)
                .frame(width: 5, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedDate = date
        }
    }

    private func numberForeground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return .white }
        if isToday { return .accentColor }
        return .primary
    }

    private func monthDayCells() -> [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: displayedMonth) else {
            return []
        }
        let firstOfMonth = interval.start
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpty = (firstWeekday - calendar.firstWeekday + 7) % 7
        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var cells: [Date?] = Array(repeating: nil, count: leadingEmpty)
        for day in 0..<daysInMonth {
            if let d = calendar.date(byAdding: .day, value: day, to: firstOfMonth) {
                cells.append(d)
            }
        }
        while cells.count % 7 != 0 {
            cells.append(nil)
        }
        return cells
    }

    private func changeMonth(_ delta: Int) {
        if let next = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = next
        }
    }
}
