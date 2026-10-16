import Foundation

/// A finished workout as the history summary needs it (SPEC D11).
public struct WorkoutFacts: Sendable {
    public var startedAt: Date
    public var durationSeconds: Int
    public var volumeKg: Double
    /// Sets per primary muscle group (SPEC D9).
    public var setsByGroup: [MuscleGroup: Int]

    public init(startedAt: Date, durationSeconds: Int, volumeKg: Double, setsByGroup: [MuscleGroup: Int] = [:]) {
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.volumeKg = volumeKg
        self.setsByGroup = setsByGroup
    }
}

public enum WorkoutVolume {
    /// Weight × reps; a set without weight or reps adds nothing.
    public static func of(weightKg: Double?, reps: Int?) -> Double {
        guard let weightKg, let reps else { return 0 }
        return weightKg * Double(reps)
    }
}

/// "Week / Month / Year" in the summary (DESIGN V9): the current calendar period.
public enum SummaryPeriod: String, CaseIterable, Sendable {
    case week, month, year

    private var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }

    /// The bars of the volume chart: days of the week, weeks touching the month, months of the year.
    private var bucketComponent: Calendar.Component {
        switch self {
        case .week: .day
        case .month: .weekOfYear
        case .year: .month
        }
    }

    public func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        calendar.dateInterval(of: component, for: date) ?? DateInterval(start: date, duration: 0)
    }

    /// Buckets up to the one containing `now`; later ones would only be empty.
    public func buckets(now: Date, calendar: Calendar) -> [DateInterval] {
        let period = interval(containing: now, calendar: calendar)
        guard var bucket = calendar.dateInterval(of: bucketComponent, for: period.start) else { return [] }
        var result: [DateInterval] = []
        while bucket.start <= now, bucket.start < period.end {
            result.append(bucket)
            guard let next = calendar.dateInterval(of: bucketComponent, for: bucket.end) else { break }
            bucket = next
        }
        return result
    }
}

/// The history summary for the current period (SPEC D11, DESIGN V9).
public struct HistorySummary: Sendable {
    public struct Bucket: Sendable, Equatable {
        public let interval: DateInterval
        public let volumeKg: Double
    }

    public let interval: DateInterval
    public let workoutCount: Int
    public let totalSeconds: Int
    public let volumeKg: Double
    public let buckets: [Bucket]
    /// Most sets first; groups without sets are left out.
    public let setsByGroup: [(group: MuscleGroup, sets: Int)]
    /// Start of every day with a workout, in the whole history: the calendar may show another month.
    public let trainingDays: Set<Date>
    public let weekStreak: Int

    public init(workouts: [WorkoutFacts], period: SummaryPeriod, now: Date, calendar: Calendar) {
        interval = period.interval(containing: now, calendar: calendar)
        let inPeriod = workouts.filter { [interval] in interval.start <= $0.startedAt && $0.startedAt < interval.end }
        workoutCount = inPeriod.count
        totalSeconds = inPeriod.reduce(0) { $0 + $1.durationSeconds }
        volumeKg = inPeriod.reduce(0) { $0 + $1.volumeKg }
        buckets = period.buckets(now: now, calendar: calendar).map { bucket in
            let volume = workouts.filter { bucket.start <= $0.startedAt && $0.startedAt < bucket.end }
                .reduce(0) { $0 + $1.volumeKg }
            return Bucket(interval: bucket, volumeKg: volume)
        }
        let groups = inPeriod.reduce(into: [MuscleGroup: Int]()) { result, workout in
            result.merge(workout.setsByGroup, uniquingKeysWith: +)
        }
        setsByGroup = MuscleGroup.allCases.compactMap { group in
            groups[group].flatMap { $0 > 0 ? (group: group, sets: $0) : nil }
        }.sorted { $0.sets > $1.sets }
        trainingDays = Set(workouts.map { calendar.startOfDay(for: $0.startedAt) })
        weekStreak = Self.weekStreak(workouts.map(\.startedAt), now: now, calendar: calendar)
    }

    /// Weeks in a row with a workout, up to this week. A week without one yet doesn't break the streak.
    public static func weekStreak(_ dates: [Date], now: Date, calendar: Calendar) -> Int {
        let weeks = Set(dates.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(week) {
            guard let previous = previousWeek(week, calendar: calendar) else { return 0 }
            week = previous
        }
        var count = 0
        while weeks.contains(week) {
            count += 1
            guard let previous = previousWeek(week, calendar: calendar) else { break }
            week = previous
        }
        return count
    }

    /// The start of the week before: found from the instant before, since a week shifted back by seven days
    /// may start at 01:00 when a clock change falls on midnight.
    private static func previousWeek(_ start: Date, calendar: Calendar) -> Date? {
        calendar.dateInterval(of: .weekOfYear, for: start.addingTimeInterval(-1))?.start
    }
}
