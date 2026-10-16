import Charts
import SwiftUI
import TrainingLoopCore

/// History summary for the current week, month or year (SPEC D11, DESIGN V9).
struct HistorySummaryView<Header: View>: View {
    @Environment(AppSettings.self) private var settings
    let workouts: [Workout]
    let exercises: [Exercise]
    @ViewBuilder let header: Header
    @State private var period = SummaryPeriod.month
    @State private var showsAllGroups = false

    private let calendar = Calendar.current

    var body: some View {
        let now = Date.now
        let groups = Dictionary(exercises.map { ($0.id, $0.primaryGroup) }, uniquingKeysWith: { first, _ in first })
        let summary = HistorySummary(workouts: workouts.map { $0.facts(groups: groups) }, period: period,
                                     now: now, calendar: calendar)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Picker("Period", selection: $period) {
                    Text("Week").tag(SummaryPeriod.week)
                    Text("Month").tag(SummaryPeriod.month)
                    Text("Year").tag(SummaryPeriod.year)
                }
                .pickerStyle(.segmented)

                Text(periodTitle(summary.interval))
                    .font(.headline)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Workouts", value: summary.workoutCount.formatted())
                    StatTile(title: "Time", value: HistoryFormat.duration(summary.totalSeconds))
                    StatTile(title: "Volume", value: HistoryFormat.totalVolume(summary.volumeKg, unit: settings.weightUnit))
                    StatTile(title: "Week Streak", value: summary.weekStreak.formatted())
                }

                card(Text(volumeTitle)) { volumeChart(summary.buckets, now: now) }
                if period != .year {
                    card(Text(verbatim: now.formatted(.dateTime.month(.wide)).capitalizedFirst)) {
                        MonthCalendar(month: now, trainingDays: summary.trainingDays, calendar: calendar)
                    }
                }
                card(Text("Sets by Muscle Group")) { groupBars(summary.setsByGroup) }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var volumeTitle: LocalizedStringKey {
        switch period {
        case .week: "Volume by Day"
        case .month: "Volume by Week"
        case .year: "Volume by Month"
        }
    }

    private func periodTitle(_ interval: DateInterval) -> String {
        switch period {
        case .week:
            let end = interval.end.addingTimeInterval(-1)
            return (interval.start..<end).formatted(.interval.day().month(.abbreviated))
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year()).capitalizedFirst
        case .year:
            return interval.start.formatted(.dateTime.year())
        }
    }

    private func card(_ title: Text, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            title.font(.subheadline.weight(.semibold))
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }

    private func volumeChart(_ buckets: [HistorySummary.Bucket], now: Date) -> some View {
        let unit = settings.weightUnit
        return Chart(Array(buckets.enumerated()), id: \.offset) { index, bucket in
            BarMark(x: .value("Period", bucketLabel(bucket.interval, now: now)),
                    y: .value("Volume", unit.fromKilograms(bucket.volumeKg)))
                .foregroundStyle(Color.accentColor.opacity(bucket.interval.contains(now) ? 0.45 : 1))
                .cornerRadius(5)
                .annotation(position: .top) {
                    if bucket.volumeKg > 0 {
                        Text(shortVolume(bucket.volumeKg))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
        }
        .chartYAxis(.hidden)
        .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
        .frame(height: 140)
    }

    private func bucketLabel(_ interval: DateInterval, now: Date) -> String {
        switch period {
        case .week: interval.start.formatted(.dateTime.weekday(.abbreviated))
        case .month: interval.contains(now) ? String(localized: "now") : interval.start.formatted(.dateTime.day().month(.abbreviated))
        case .year: interval.start.formatted(.dateTime.month(.narrow))
        }
    }

    /// "5.2" tonnes over a bar; pounds in thousands.
    private func shortVolume(_ kilograms: Double) -> String {
        let value = settings.weightUnit.fromKilograms(kilograms) / 1000
        return value.formatted(.number.precision(.fractionLength(value < 10 ? 1 : 0)))
    }

    @ViewBuilder
    private func groupBars(_ groups: [(group: MuscleGroup, sets: Int)]) -> some View {
        if groups.isEmpty {
            Text("No sets in this period.")
                .foregroundStyle(.secondary)
        } else {
            let top = groups.first?.sets ?? 1
            let shown = showsAllGroups ? groups : Array(groups.prefix(3))
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(shown, id: \.group) { item in
                    GridRow {
                        Text(item.group.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(height: 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .scaleEffect(x: CGFloat(item.sets) / CGFloat(top), anchor: .leading)
                        Text(item.sets.formatted())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            if groups.count > 3 {
                Button(showsAllGroups ? String(localized: "Show Less")
                                      : String(localized: "\(groups.count - 3) more groups")) {
                    withAnimation { showsAllGroups.toggle() }
                }
                .font(.subheadline)
            }
        }
    }
}

/// The month with training days filled in (DESIGN V9).
private struct MonthCalendar: View {
    let month: Date
    let trainingDays: Set<Date>
    let calendar: Calendar

    var body: some View {
        let days = cells
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day {
                    dayCell(day)
                } else {
                    Color.clear.frame(height: 30)
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let trained = trainingDays.contains(day)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date.now
        return Text(calendar.component(.day, from: day).formatted())
            .font(.footnote.weight(trained ? .semibold : .regular))
            .monospacedDigit()
            .foregroundStyle(trained ? Color.white : isFuture ? Color.secondary.opacity(0.5) : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background {
                if trained { Circle().fill(Color.accentColor) }
            }
            .overlay {
                if isToday { Circle().strokeBorder(Color.accentColor, lineWidth: 1.5) }
            }
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
            .accessibilityAddTraits(trained ? .isSelected : [])
    }

    /// Short weekday names, starting on the locale's first day of the week.
    private var weekdaySymbols: [String] {
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first]).map(\.capitalizedFirst)
    }

    /// nil cells before the 1st, then every day of the month.
    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        var result: [Date?] = Array(repeating: nil, count: leading)
        var day = interval.start
        while day < interval.end {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }
}

extension String {
    /// "октябрь 2026" → "Октябрь 2026".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
