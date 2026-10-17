import Foundation
import SwiftData
import Testing
@testable import TrainingLoop
import TrainingLoopCore

/// TECH T12: a full History (3000 workouts ≈ 60k sets) on disk, and the time of what reads it.
/// Off by default; run with `TEST_RUNNER_TL_BENCHMARK=1 xcodebuild test -only-testing:TrainingLoopTests/LargeHistoryBenchmark`.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TL_BENCHMARK"] != nil))
struct LargeHistoryBenchmark {
    static let workoutCount = Limits.maxWorkouts
    static let exerciseCount = 20
    static let exercisesPerWorkout = 5
    static let setsPerExercise = 4

    @Test func measure() throws {
        let url = URL.temporaryDirectory.appending(path: "benchmark-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path() + suffix) }
        }
        let exerciseIDs = try seed(at: url)

        // A store opened afresh, as at launch: nothing is in memory yet.
        let container = try Self.container(at: url)
        let context = container.mainContext
        var lines: [String] = []
        func time<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
            let clock = ContinuousClock()
            var result: T?
            let duration = try clock.measure { result = try work() }
            lines.append("\(name): \(duration.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))")
            return result!
        }

        let workouts = try time("fetch History") {
            try context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isActive },
                                                       sortBy: [SortDescriptor(\.startedAt, order: .reverse)]))
        }
        #expect(workouts.count == Self.workoutCount)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let groups = Dictionary(exercises.map { ($0.id, $0.primaryGroup) }, uniquingKeysWith: { first, _ in first })
        for period in [SummaryPeriod.month, .year, .week] {
            _ = time("summary \(period)") { summary(workouts, groups: groups, period: period) }
        }
        let squat = exerciseIDs[0]
        let stats = time("exercise statistics") {
            ExerciseStats(sessions: context.exerciseWorkouts(squat).map { .init(date: $0.workout.startedAt, sets: $0.sets) })
        }
        #expect(stats.workoutCount > 0)
        let used = Array(exerciseIDs.prefix(Self.exercisesPerWorkout))
        _ = time("records history at start (5 exercises)") { context.recordHistory(of: used) }
        _ = time("last sets at start (5 exercises)") { context.lastSets(of: used) }
        time("recount after save (5 exercises)") { context.refreshRecords(of: used) }
        time("recount all, once after update") { context.refreshRecords(of: exerciseIDs) }

        let report = lines.joined(separator: "\n")
        print("LargeHistoryBenchmark (\(Self.workoutCount) workouts, \(Self.workoutCount * Self.exercisesPerWorkout * Self.setsPerExercise) sets)\n\(report)")
        Attachment.record(report, named: "benchmark.txt")
    }

    /// What `HistorySummaryView` works out on every render.
    private func summary(_ workouts: [Workout], groups: [UUID: MuscleGroup], period: SummaryPeriod) -> HistorySummary {
        let now = Date.now
        let calendar = Calendar.current
        let interval = period.interval(containing: now, calendar: calendar)
        let facts = workouts.map { workout in
            workout.facts(groups: interval.start <= workout.startedAt && workout.startedAt < interval.end ? groups : nil)
        }
        return HistorySummary(workouts: facts, period: period, now: now, calendar: calendar)
    }

    private static func container(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: Schema(versionedSchema: SchemaV1.self), configurations: ModelConfiguration(url: url))
    }

    /// One workout a day back from today, five of twenty exercises in turn, four sets each, weights rising.
    private func seed(at url: URL) throws -> [UUID] {
        let container = try Self.container(at: url)
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let groups = MuscleGroup.allCases
        let exercises = (0..<Self.exerciseCount).map { index in
            Exercise(name: "Exercise \(index)", measure: .reps, weighted: true,
                     primaryGroup: groups[index % groups.count], equipment: .barbell)
        }
        exercises.forEach(context.insert)
        let today = Calendar.current.startOfDay(for: .now)
        for number in 0..<Self.workoutCount {
            let daysAgo = Self.workoutCount - 1 - number
            let start = today.addingTimeInterval(TimeInterval(-daysAgo * 86_400 + 18 * 3600 - 86_400))
            let workout = Workout(name: "Workout \(number % 3)", startedAt: start)
            workout.isActive = false
            workout.endedAt = start.addingTimeInterval(3600)
            context.insert(workout)
            for order in 0..<Self.exercisesPerWorkout {
                let exercise = exercises[(number + order * 4) % Self.exerciseCount]
                let entry = WorkoutEntry(exerciseID: exercise.id, order: order, restSeconds: 90)
                workout.entries?.append(entry)
                let weight = 40 + Double(number % 400) / 10
                for index in 0..<Self.setsPerExercise {
                    entry.sets?.append(WorkoutSet(order: index, reps: 8 - index, weightKg: weight,
                                                  exerciseID: exercise.id, workoutStartedAt: start))
                }
            }
            workout.updateTotals()
            if number % 250 == 249 { try context.save() }
        }
        try context.save()
        return exercises.map(\.id)
    }
}
