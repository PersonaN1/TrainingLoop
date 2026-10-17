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

    @Test func measure() async throws {
        let url = URL.temporaryDirectory.appending(path: "benchmark-\(UUID().uuidString).store")
        defer {
            for suffix in ["", "-shm", "-wal"] { try? FileManager.default.removeItem(atPath: url.path() + suffix) }
        }
        let exerciseIDs = try seed(at: url)
        // A store opened afresh, as at launch; every step reads through a new context, so nothing is cached.
        let container = try Self.container(at: url)
        let squat = exerciseIDs[0]
        let used = Array(exerciseIDs.prefix(Self.exercisesPerWorkout))
        let calendar = Calendar.current
        var lines = ["step: main thread blocked, before → after (result ready after)"]

        func compare(_ name: String, before: @MainActor (ModelContext) -> Void, after: @MainActor () async -> Void) async {
            let old = await Self.stall { before(ModelContext(container)) }
            let new = await Self.stall { await after() }
            lines.append("\(name): \(Self.ms(old.stall)) → \(Self.ms(new.stall)) (\(Self.ms(new.total)))")
        }

        for period in [SummaryPeriod.week, .month, .year] {
            await compare("summary \(period)") { context in
                _ = summary(context, period: period)
            } after: {
                _ = await HistoryReader.read(container) { await $0.summary(period: period, now: .now, calendar: calendar) }
            }
        }
        await compare("exercise statistics") { context in
            _ = ExerciseStats(sessions: context.exerciseWorkouts(squat).map { .init(date: $0.workout.startedAt, sets: $0.sets) })
        } after: {
            _ = await HistoryReader.read(container) { await $0.exerciseHistory(squat) }
        }
        await compare("records history at start (5 exercises)") { context in
            _ = context.recordHistory(of: used)
        } after: {
            _ = await HistoryReader.read(container) { await $0.recordHistory(of: used) }
        }
        await compare("recount after save (5 exercises)") { context in
            context.refreshRecords(of: used)
        } after: {
            RecordRecount.start(used, context: container.mainContext)
            await RecordRecount.finish()
        }

        let report = lines.joined(separator: "\n")
        print("LargeHistoryBenchmark (\(Self.workoutCount) workouts, \(Self.workoutCount * Self.exercisesPerWorkout * Self.setsPerExercise) sets)\n\(report)")
        Attachment.record(report, named: "benchmark.txt")
    }

    /// The longest the main actor went without a turn while `work` ran, and how long `work` took.
    private static func stall(_ work: @MainActor () async -> Void) async -> (stall: Duration, total: Duration) {
        let clock = ContinuousClock()
        let ticker = Task { @MainActor in
            var last = clock.now
            var worst = Duration.zero
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2))
                let now = clock.now
                worst = max(worst, now - last)
                last = now
            }
            return worst
        }
        await Task.yield()
        let start = clock.now
        await work()
        let total = clock.now - start
        // One more turn, so a stall at the very end is counted.
        try? await Task.sleep(for: .milliseconds(5))
        ticker.cancel()
        return (await ticker.value, total)
    }

    private static func ms(_ duration: Duration) -> String {
        duration.formatted(.units(allowed: [.milliseconds], fractionalPart: .hide))
    }

    /// What `HistorySummaryView` worked out on every render before it moved to `HistoryReader`.
    private func summary(_ context: ModelContext, period: SummaryPeriod) -> HistorySummary {
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isActive }))) ?? []
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        let groups = Dictionary(exercises.map { ($0.id, $0.primaryGroup) }, uniquingKeysWith: { first, _ in first })
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

    /// A full History over twenty exercises.
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
        SampleHistory.insertFull(exercises.map(\.id), into: context, count: Self.workoutCount)
        return exercises.map(\.id)
    }
}
