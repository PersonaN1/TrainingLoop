import SwiftUI
import TrainingLoopCore

/// Text for the history list, a workout record and the summary (DESIGN V9).
enum HistoryFormat {
    /// "52 min", "1 hr, 5 min"; a zero hour is left out.
    static func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        return Duration.seconds(minutes * 60)
            .formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }

    /// "4,220 kg" in a row; "no weight" when nothing was lifted.
    static func volume(_ kilograms: Double, unit: WeightUnit) -> String {
        kilograms > 0 ? wholeWeight(kilograms, unit: unit) : String(localized: "no weight")
    }

    /// "36.4 t" in a summary tile; pounds stay whole.
    static func totalVolume(_ kilograms: Double, unit: WeightUnit) -> String {
        guard unit == .kg, kilograms >= 1000 else { return wholeWeight(kilograms, unit: unit) }
        let tonnes = (kilograms / 1000).formatted(.number.precision(.fractionLength(0...1)))
        return String(localized: "\(tonnes) t")
    }

    private static func wholeWeight(_ kilograms: Double, unit: WeightUnit) -> String {
        let value = unit.fromKilograms(kilograms).rounded().formatted(.number.precision(.fractionLength(0)))
        return switch unit {
        case .kg: String(localized: "\(value) kg")
        case .lb: String(localized: "\(value) lb")
        }
    }

    /// "18:05 · 52 min · 4,220 kg".
    static func meta(_ workout: Workout, unit: WeightUnit) -> String {
        [workout.startedAt.formatted(date: .omitted, time: .shortened),
         duration(workout.durationSeconds),
         volume(workout.totalVolumeKg, unit: unit)].joined(separator: " · ")
    }

    /// "Today", "Yesterday", "Wednesday, 14 October"; the year only when it isn't this one.
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return String(localized: "Today") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        var style = Date.FormatStyle().weekday(.wide).day().month(.wide)
        if !calendar.isDate(date, equalTo: now, toGranularity: .year) { style = style.year() }
        return date.formatted(style).capitalizedFirst
    }
}

/// A title, a big value: the summary tiles (DESIGN V9).
struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }
}
