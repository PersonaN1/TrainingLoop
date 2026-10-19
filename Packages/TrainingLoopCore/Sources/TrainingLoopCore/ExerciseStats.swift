import Foundation

/// An exercise's statistics from its history: chart points, record tiles, best weight for reps
/// (SPEC D10, DESIGN V7).
public struct ExerciseStats: Sendable {
    /// One workout's sets of the exercise, in the order they were done.
    public struct Session: Sendable {
        public var date: Date
        public var sets: [PlannedSet]

        public init(date: Date, sets: [PlannedSet]) {
            self.date = date
            self.sets = sets
        }
    }

    /// What the chart shows: one value per workout.
    public enum Metric: Hashable, CaseIterable, Sendable {
        /// The heaviest real set.
        case bestWeight
        /// Weight × reps of all sets.
        case volume
        case maxReps
        case totalReps
        case maxSeconds

        /// The chart's choices: weight first (V7); no 1RM chart.
        public static func available(measure: Measure, weighted: Bool) -> [Metric] {
            switch measure {
            case .time: [.maxSeconds]
            case .reps: weighted ? [.bestWeight, .volume] : [.maxReps, .totalReps]
            }
        }

        /// The better side counts for a best, both sides for a total (D23).
        func value(of sets: [PlannedSet]) -> Double? {
            let sides = sets.flatMap(\.sides)
            let value: Double? = switch self {
            case .bestWeight: sides.compactMap(\.weightKg).max()
            case .volume: PersonalBests.volume(of: sets)
            case .maxReps: sides.compactMap(\.reps).max().map(Double.init)
            case .totalReps: Double(sides.compactMap(\.reps).reduce(0, +))
            case .maxSeconds: sides.compactMap(\.seconds).max().map(Double.init)
            }
            guard let value, value > 0 else { return nil }
            return value
        }
    }

    public struct Point: Equatable, Sendable {
        /// Index into `sessions`.
        public var session: Int
        public var date: Date
        public var value: Double
        /// The all-time best of this metric (coral with 🏆): one point, the earliest of equal ones.
        /// Records broken along the way stay in History.
        public var isRecord: Bool
    }

    /// A best value and where it came from.
    public struct Highlight: Equatable, Sendable {
        public var value: Double
        /// The set behind it; nil for a workout's volume.
        public var set: PlannedSet?
        public var date: Date
    }

    /// Oldest first.
    public let sessions: [Session]
    /// Each session's records, as in History (🏆).
    public let records: [ExerciseWorkoutRecords]

    public init(sessions: [Session]) {
        self.sessions = sessions.sorted { $0.date < $1.date }
        records = PersonalBests.records(of: self.sessions.map(\.sets))
    }

    public var workoutCount: Int { sessions.count }

    /// Some set was done with weight; without it a weighted exercise charts reps (push-ups with
    /// optional added weight).
    public var hasWeight: Bool {
        sessions.contains { $0.sets.flatMap(\.sides).contains { ($0.weightKg ?? 0) > 0 } }
    }

    /// One point per workout that has a value, oldest first; the peak is the record.
    public func points(_ metric: Metric) -> [Point] {
        var points = sessions.indices.compactMap { index in
            metric.value(of: sessions[index].sets).map {
                Point(session: index, date: sessions[index].date, value: $0, isRecord: false)
            }
        }
        var peak: Int?
        for index in points.indices where points[index].value > (peak.map { points[$0].value } ?? 0) + 1e-6 {
            peak = index
        }
        if let peak { points[peak].isRecord = true }
        return points
    }

    /// The heaviest real set; of equal weights the one with more reps, then the earliest.
    public var bestWeight: Highlight? {
        best { set in set.weightKg.flatMap { $0 > 0 ? $0 + Double(set.reps ?? 0) / 10_000 : nil } }
            .map { Highlight(value: $0.set?.weightKg ?? 0, set: $0.set, date: $0.date) }
    }

    /// The highest Epley estimate (`OneRepMax`): a reference value, never a record.
    public var estimatedMax: Highlight? {
        best { set in set.weightKg.flatMap { weight in set.reps.flatMap { OneRepMax.estimate(weightKg: weight, reps: $0) } } }
    }

    public var maxReps: Highlight? {
        best { set in set.reps.flatMap { $0 > 0 ? Double($0) : nil } }
    }

    public var maxSeconds: Highlight? {
        best { set in set.seconds.flatMap { $0 > 0 ? Double($0) : nil } }
    }

    /// The most volume in one workout.
    public var bestVolume: Highlight? {
        var result: Highlight?
        for session in sessions {
            let volume = PersonalBests.volume(of: session.sets)
            if volume > (result?.value ?? 0) + 1e-6 { result = Highlight(value: volume, set: nil, date: session.date) }
        }
        return result
    }

    /// The heaviest real set with at least this many reps, for each of `RecordMetric.repTargets`
    /// that has one.
    public var bestWeightForReps: [(reps: Int, best: Highlight)] {
        RecordMetric.repTargets.compactMap { target in
            best { set in
                guard let weight = set.weightKg, weight > 0, let reps = set.reps, reps >= target else { return nil }
                return weight
            }
            .map { (target, $0) }
        }
    }

    /// The set side with the highest score; the earliest wins a tie.
    private func best(_ score: (PlannedSet) -> Double?) -> Highlight? {
        var result: Highlight?
        for session in sessions {
            for set in session.sets.flatMap(\.sides) {
                guard let value = score(set), value > (result?.value ?? -.infinity) else { continue }
                result = Highlight(value: value, set: set, date: session.date)
            }
        }
        return result
    }
}
