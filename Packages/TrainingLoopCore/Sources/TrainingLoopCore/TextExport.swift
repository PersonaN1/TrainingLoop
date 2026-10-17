import Foundation

/// A template, a workout or a period as plain text for a messenger (SPEC D12, TECH T11).
/// Words come from the `Export` String Catalog in the given locale's language; weights in `unit`.
public struct TextExport {
    /// What the text needs to know about an exercise.
    public struct ExerciseInfo: Sendable {
        public var name: String
        /// Bodyweight equipment: a weight is added to the body, "+5 kg × 6".
        public var addsWeight: Bool

        public init(name: String, addsWeight: Bool) {
            self.name = name
            self.addsWeight = addsWeight
        }
    }

    /// A finished workout: its exercises and done sets as a definition, like the record editor.
    public struct Workout: Sendable {
        public var name: String
        public var startedAt: Date
        public var durationSeconds: Int
        public var note: String
        public var definition: TemplateDefinition

        public init(name: String, startedAt: Date, durationSeconds: Int, note: String, definition: TemplateDefinition) {
            self.name = name
            self.startedAt = startedAt
            self.durationSeconds = durationSeconds
            self.note = note
            self.definition = definition
        }
    }

    public var unit: WeightUnit
    public var locale: Locale
    public var calendar: Calendar
    private let exercise: (UUID) -> ExerciseInfo

    public init(unit: WeightUnit, locale: Locale, calendar: Calendar = .current,
                exercise: @escaping (UUID) -> ExerciseInfo) {
        self.unit = unit
        self.locale = locale
        self.calendar = calendar
        self.exercise = exercise
    }

    // MARK: Texts

    /// "Legs + Pull-ups", "5 exercises · 15 sets · ~40 min", then the exercises with planned sets and rests.
    public func template(name: String, definition: TemplateDefinition) -> String {
        var summary = [localized("\(definition.exercises.count) exercises"),
                       localized("\(definition.setCount) sets")]
        if let minutes = definition.estimatedMinutes { summary.append(localized("~\(minutes) min")) }
        let blocks = definition.items.map { item -> String in
            switch item {
            case .exercise(let exercise):
                return exerciseLine(exercise, planned: true)
                    + (exercise.restSeconds > 0 ? " · " + localized("rest \(clock(exercise.restSeconds))") : "")
            case .superset(let superset):
                let rounds = superset.exercises.map(\.sets.count).max() ?? 0
                let header = [localized("Superset"), localized("\(rounds) rounds"),
                              localized("rest \(clock(superset.restWithinSeconds)) / \(clock(superset.restAfterSeconds))")]
                return ([header.joined(separator: " · ")]
                        + superset.exercises.map { "– " + exerciseLine($0, planned: true) }).joined(separator: "\n")
            }
        }
        return ([name + "\n" + summary.joined(separator: " · ")] + blocks).joined(separator: "\n\n")
    }

    /// Name; "Wed, 14 October 2026 · 18:05 · 52 min"; every exercise with every done set; totals and the note.
    public func workout(_ workout: Workout) -> String {
        workoutBody(workout, withYear: true)
    }

    /// "TrainingLoop · 1–31 October 2026", the period's totals, then the workouts oldest first.
    /// `interval` is the chosen period; nil means all of them: from the first workout to the last.
    public func period(_ workouts: [Workout], interval: DateInterval?) -> String {
        let sorted = workouts.sorted { $0.startedAt < $1.startedAt }
        var header = "TrainingLoop"
        if let first = sorted.first?.startedAt, let last = sorted.last?.startedAt {
            let start = interval?.start ?? first
            // The interval's end is exclusive: its last day is the one before.
            let end = interval.map { max($0.start, $0.end.addingTimeInterval(-1)) } ?? last
            header += " · " + dayRange(start, end)
        }
        var totals = [localized("\(sorted.count) workouts"),
                      duration(sorted.reduce(0) { $0 + $1.durationSeconds })]
        let volume = sorted.reduce(0) { $0 + Self.volume($1.definition) }
        if volume > 0 { totals.append(wholeWeight(volume)) }
        let spansYears = sorted.first.map { first in
            sorted.contains { !calendar.isDate($0.startedAt, equalTo: first.startedAt, toGranularity: .year) }
        } ?? false
        let bodies = sorted.map { "———\n" + workoutBody($0, withYear: spansYears) }
        return ([header + "\n" + totals.joined(separator: " · ")] + bodies).joined(separator: "\n\n")
    }

    // MARK: Parts

    private func workoutBody(_ workout: Workout, withYear: Bool) -> String {
        let definition = workout.definition
        let when = [day(workout.startedAt, withYear: withYear),
                    workout.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened,
                                                                 locale: locale, calendar: calendar,
                                                                 timeZone: calendar.timeZone)),
                    duration(workout.durationSeconds)]
        let blocks = definition.items.map { item -> String in
            switch item {
            case .exercise(let exercise):
                return exerciseLine(exercise, planned: false)
            case .superset(let superset):
                return ([localized("Superset")] + superset.exercises.map { "– " + exerciseLine($0, planned: false) })
                    .joined(separator: "\n")
            }
        }
        var totals = [localized("\(definition.exercises.count) exercises"), localized("\(definition.setCount) sets")]
        let volume = Self.volume(definition)
        if volume > 0 { totals.append(wholeWeight(volume)) }
        var tail = localized("Total: \(totals.joined(separator: " · "))")
        let note = workout.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { tail += "\n" + localized("Note: \(note)") }
        return ([workout.name + "\n" + when.joined(separator: " · ")] + blocks + [tail]).joined(separator: "\n\n")
    }

    /// "Romanian Deadlift: 80 kg × 10, 80 kg × 8". A template's identical sets fold: "4 × 8 · 60 kg", "3 sets".
    private func exerciseLine(_ item: TemplateExercise, planned: Bool) -> String {
        let info = exercise(item.exerciseID)
        let sets: String
        if item.sets.isEmpty {
            sets = "—"
        } else if planned, let first = item.sets.first, item.sets.allSatisfy({ $0 == first }) {
            var parts: [String] = []
            if let value = value(first) {
                parts.append("\(item.sets.count) × \(value)")
            } else {
                parts.append(localized("\(item.sets.count) sets"))
            }
            if let weight = first.weightKg { parts.append(signedWeight(weight, adds: info.addsWeight)) }
            sets = parts.joined(separator: " · ")
        } else {
            sets = item.sets.map { set(_: $0, adds: info.addsWeight) }.joined(separator: ", ")
        }
        return "\(info.name): \(sets)"
    }

    /// "80 kg × 10", "+5 kg × 6", "8", "0:45", "60 kg"; "—" for a set with nothing in it.
    private func set(_ set: PlannedSet, adds: Bool) -> String {
        let weight = set.weightKg.map { signedWeight($0, adds: adds) }
        switch (weight, value(set)) {
        case let (weight?, value?): return "\(weight) × \(value)"
        case let (weight?, nil): return weight
        case let (nil, value?): return value
        case (nil, nil): return "—"
        }
    }

    /// Reps or time of a set.
    private func value(_ set: PlannedSet) -> String? {
        if let seconds = set.seconds { return clock(seconds) }
        return set.reps.map { $0.formatted(.number.locale(locale)) }
    }

    private func signedWeight(_ kilograms: Double, adds: Bool) -> String {
        (adds ? "+" : "") + weight(kilograms)
    }

    /// "62.5 kg", up to two decimals.
    private func weight(_ kilograms: Double) -> String {
        unitText(unit.fromKilograms(kilograms).formatted(.number.precision(.fractionLength(0...2)).locale(locale)))
    }

    /// "4,220 kg" for totals.
    private func wholeWeight(_ kilograms: Double) -> String {
        unitText(unit.fromKilograms(kilograms).rounded().formatted(.number.precision(.fractionLength(0)).locale(locale)))
    }

    private func unitText(_ value: String) -> String {
        switch unit {
        case .kg: localized("\(value) kg")
        case .lb: localized("\(value) lb")
        }
    }

    /// "0:45", "1:30".
    private func clock(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// "52 min", "1 hr, 5 min".
    private func duration(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        var style = Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .abbreviated)
        style.locale = locale
        return Duration.seconds(minutes * 60).formatted(style)
    }

    /// "Wed, 14 October 2026".
    private func day(_ date: Date, withYear: Bool) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            .weekday(.abbreviated).day().month(.wide)
        if withYear { style = style.year() }
        return date.formatted(style).capitalizedFirst
    }

    /// "1–31 October 2026"; one day alone when the period is a day.
    private func dayRange(_ start: Date, _ end: Date) -> String {
        var style = Date.IntervalFormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.day().month(.wide).year()
        return (start..<max(start, end)).formatted(style)
    }

    private static func volume(_ definition: TemplateDefinition) -> Double {
        definition.exercises.flatMap(\.sets).reduce(0) { $0 + WorkoutVolume.of(weightKg: $1.weightKg, reps: $1.reps) }
    }

    private func localized(_ value: String.LocalizationValue) -> String {
        String(localized: LocalizedStringResource(value, table: "Export", locale: locale,
                                                  bundle: .atURL(Bundle.module.bundleURL)))
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
