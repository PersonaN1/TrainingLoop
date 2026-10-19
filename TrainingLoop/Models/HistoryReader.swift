import Foundation
import SwiftData
import TrainingLoopCore

/// Reads that walk much of History, off the main thread (TECH T12). With a full History (3000 workouts,
/// ≈ 60k sets) each takes from a few hundred milliseconds to seconds, nearly all of it loading rows.
/// Results come back as plain values; the main context does the writing.
/// Each read gets a reader of its own: a fresh context sees the store as last saved.
@ModelActor
actor HistoryReader {
    /// Runs `read` on a new reader away from the main actor: a reader made on the main actor would
    /// do its work there.
    nonisolated static func read<T: Sendable>(_ container: ModelContainer,
                                              _ read: @escaping @Sendable (HistoryReader) async -> T) async -> T {
        await Task.detached(priority: .userInitiated) {
            await read(HistoryReader(modelContainer: container))
        }.value
    }

    /// The History summary for the current period (SPEC D11).
    func summary(period: SummaryPeriod, now: Date, calendar: Calendar) -> HistorySummary {
        let workouts = (try? modelContext.fetch(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isActive }))) ?? []
        let exercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        let muscles = Dictionary(exercises.map { ($0.id, $0.groupAndMuscles) }, uniquingKeysWith: { first, _ in first })
        // Sets by group and muscle only matter in the period: counting them elsewhere would load every set in History.
        let interval = period.interval(containing: now, calendar: calendar)
        let facts = workouts.map { workout in
            workout.facts(muscles: interval.start <= workout.startedAt && workout.startedAt < interval.end ? muscles : nil)
        }
        return HistorySummary(workouts: facts, period: period, now: now, calendar: calendar)
    }

    struct ExerciseWorkout: Sendable {
        let workoutID: PersistentIdentifier
        let name: String
        let startedAt: Date
        let sets: [PlannedSet]
    }

    /// An exercise's finished workouts, oldest first, and its statistics (D10).
    func exerciseHistory(_ exerciseID: UUID) -> (workouts: [ExerciseWorkout], stats: ExerciseStats) {
        let workouts = modelContext.exerciseWorkouts(exerciseID).map {
            ExerciseWorkout(workoutID: $0.workout.persistentModelID, name: $0.workout.name,
                            startedAt: $0.workout.startedAt, sets: $0.sets)
        }
        let stats = ExerciseStats(sessions: workouts.map { .init(date: $0.startedAt, sets: $0.sets) })
        return (workouts, stats)
    }

    /// Each exercise's catalog line (D8), from one pass over all recorded sets.
    func exerciseSummaries(measures: [UUID: Measure]) -> [UUID: ExerciseSummary] {
        var descriptor = FetchDescriptor<WorkoutSet>()
        descriptor.propertiesToFetch = [\.reps, \.seconds, \.weightKg, \.exerciseID, \.workoutStartedAt]
        let sets: [WorkoutSet]
        do {
            sets = try modelContext.fetch(descriptor)
        } catch {
            Persistence.report("Fetching sets failed", error)
            return [:]
        }
        let byExercise = Dictionary(grouping: sets, by: \.exerciseID)
        return byExercise.reduce(into: [:]) { result, item in
            // Each side of a set by sides counts on its own: the best is the better side (SPEC D23).
            let performed = item.value.flatMap { set in
                set.planned.sides.map {
                    PerformedSet(reps: $0.reps, seconds: $0.seconds, weightKg: $0.weightKg,
                                 workoutStartedAt: set.workoutStartedAt)
                }
            }
            result[item.key] = ExerciseSummary(sets: performed, measure: measures[item.key] ?? .reps)
        }
    }

    func recordHistory(of exerciseIDs: [UUID]) -> [UUID: [[PlannedSet]]] {
        modelContext.recordHistory(of: exerciseIDs)
    }

    func recordCountChanges(of exerciseIDs: Set<UUID>) -> [PersistentIdentifier: Int] {
        modelContext.recordCountChanges(of: exerciseIDs)
    }
}

/// Records are counted again after History changes (D10, DESIGN V9) in the background, one count after
/// another, so a later change is never overwritten by an earlier one. Only the counts that changed,
/// usually a few, are written on the main context: views see them at once.
@MainActor
enum RecordRecount {
    private static var last: Task<Void, Never>?

    /// Call once the change is saved.
    static func start(_ exerciseIDs: some Sequence<UUID>, context: ModelContext) {
        let ids = Set(exerciseIDs)
        guard !ids.isEmpty else { return }
        let container = context.container
        let previous = last
        last = Task {
            await previous?.value
            let changes = await HistoryReader.read(container) { await $0.recordCountChanges(of: ids) }
            context.applyRecordCounts(changes)
        }
    }

    /// Waits for the counts started so far.
    static func finish() async {
        await last?.value
    }
}
