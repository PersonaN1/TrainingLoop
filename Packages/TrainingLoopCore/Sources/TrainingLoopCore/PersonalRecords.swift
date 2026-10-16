import Foundation

/// What a record is kept for (CONTEXT: Personal record, SPEC D10). The estimated 1RM never is.
public enum RecordMetric: Hashable, Sendable {
    /// The heaviest set at any reps.
    case weight
    /// The heaviest set with at least this many reps.
    case weightForReps(Int)
    /// The most reps in a set without weight.
    case reps
    /// The longest set on time.
    case seconds
    /// The most weight × reps of one exercise in one workout.
    case volume

    public static let repTargets = [1, 3, 5, 8, 10]

    /// The order of lines on the summary.
    var rank: Int {
        switch self {
        case .weight: 0
        case .weightForReps(let reps): reps
        case .reps: 100
        case .seconds: 101
        case .volume: 102
        }
    }

    /// The values one set reaches; volume is per workout, so it isn't here.
    public static func values(of set: PlannedSet) -> [RecordMetric: Double] {
        var values: [RecordMetric: Double] = [:]
        if let weight = set.weightKg, weight > 0 {
            values[.weight] = weight
            if let reps = set.reps {
                for target in repTargets where reps >= target { values[.weightForReps(target)] = weight }
            }
        } else if let reps = set.reps, reps > 0 {
            values[.reps] = Double(reps)
        }
        if let seconds = set.seconds, seconds > 0 { values[.seconds] = Double(seconds) }
        return values
    }
}

/// An exercise's best values so far. A metric with no earlier value can't be beaten:
/// the first workout of an exercise sets no records.
public struct PersonalBests: Equatable, Sendable {
    public private(set) var values: [RecordMetric: Double] = [:]

    public init() {}

    /// From history: each element is one workout's sets of the exercise.
    public init(workouts: [[PlannedSet]]) {
        for sets in workouts {
            for set in sets { _ = add(set) }
            _ = addVolume(Self.volume(of: sets))
        }
    }

    /// Takes a set in; returns the metrics it beat.
    public mutating func add(_ set: PlannedSet) -> Set<RecordMetric> {
        var beaten = Set<RecordMetric>()
        for (metric, value) in RecordMetric.values(of: set) {
            if let best = values[metric], value > best { beaten.insert(metric) }
            values[metric] = max(values[metric] ?? 0, value)
        }
        return beaten
    }

    /// Takes one workout's volume in; true when it beat the best.
    public mutating func addVolume(_ volume: Double) -> Bool {
        guard volume > 0 else { return false }
        defer { values[.volume] = max(values[.volume] ?? 0, volume) }
        guard let best = values[.volume] else { return false }
        return volume > best
    }

    static func volume(of sets: [PlannedSet]) -> Double {
        sets.reduce(0) { $0 + WorkoutVolume.of(weightKg: $1.weightKg, reps: $1.reps) }
    }
}

/// The records of a workout in progress: 🏆 at the sets during it, a list on the summary (D10, DESIGN V8).
public struct WorkoutRecords: Equatable, Sendable {
    public struct Record: Equatable, Sendable {
        public var exerciseID: UUID
        public var metric: RecordMetric
        /// The set behind it; nil for volume.
        public var set: PlannedSet?
        /// The exercise's volume in this workout, for `.volume`.
        public var volumeKg: Double?
    }

    /// Sets that beat a record when they were ticked.
    public var setIDs: Set<UUID> = []
    /// One line per record, in workout order: the final value of each metric. Records of one set are
    /// folded: "Weight" covers its rep records, and of those only the most reps stays.
    public var records: [Record] = []

    public init() {}
}

extension ActiveWorkout {
    /// `history` holds each exercise's earlier workouts, as in `PersonalBests(workouts:)`.
    public func records(history: [UUID: [[PlannedSet]]]) -> WorkoutRecords {
        var result = WorkoutRecords()
        let exercises = items.flatMap(\.exercises)
        let exerciseIDs = exercises.map(\.exerciseID).reduce(into: [UUID]()) { if !$0.contains($1) { $0.append($1) } }
        for exerciseID in exerciseIDs {
            var bests = PersonalBests(workouts: history[exerciseID] ?? [])
            let done = exercises.filter { $0.exerciseID == exerciseID }
                .flatMap(\.sets)
                .filter(\.isDone)
                .sorted { $0.doneAt! < $1.doneAt! }
            // The last set to beat each metric holds it.
            var holders: [RecordMetric: SetRow] = [:]
            var metricOrder: [RecordMetric] = []
            for set in done {
                let beaten = bests.add(set.value)
                if !beaten.isEmpty { result.setIDs.insert(set.id) }
                for metric in beaten.sorted(by: { $0.rank < $1.rank }) {
                    if holders[metric] == nil { metricOrder.append(metric) }
                    holders[metric] = set
                }
            }
            let volume = PersonalBests.volume(of: done.map(\.value))
            let volumeBeaten = bests.addVolume(volume)

            var lines: [WorkoutRecords.Record] = []
            for metric in metricOrder {
                guard let holder = holders[metric] else { continue }
                if case .weightForReps(let target) = metric {
                    if holders[.weight]?.id == holder.id { continue }
                    let more = holders.contains { other, set in
                        if case .weightForReps(let otherTarget) = other { otherTarget > target && set.id == holder.id }
                        else { false }
                    }
                    if more { continue }
                }
                lines.append(.init(exerciseID: exerciseID, metric: metric, set: holder.value))
            }
            if volumeBeaten {
                lines.append(.init(exerciseID: exerciseID, metric: .volume, volumeKg: volume))
            }
            result.records += lines
        }
        return result
    }
}
