import Foundation
import SwiftData
import Testing
@testable import TrainingLoop
import TrainingLoopCore

/// Editing, moving or deleting a past workout counts records and statistics again (D10, D16).
@MainActor
struct EditingHistoryTests {
    let store: TestStore
    let squat: Exercise

    init() throws {
        store = try TestStore()
        squat = store.exercise()
    }

    private var stats: ExerciseStats {
        ExerciseStats(sessions: store.context.exerciseWorkouts(squat.id).map {
            .init(date: $0.workout.startedAt, sets: $0.sets)
        })
    }

    @Test func editingEarlierWorkoutTakesLaterRecordsAway() async {
        let first = await store.addWorkout(on: 1, squat.id, weightKg: 60)
        let second = await store.addWorkout(on: 3, squat.id, weightKg: 70)
        #expect(first.recordCount == 0)
        #expect(second.recordCount > 0)

        // The first workout was actually heavier: the second one beats nothing now.
        await store.edit(first, squat.id, weightKg: 80)

        #expect(first.recordCount == 0)
        #expect(second.recordCount == 0)
        #expect(first.totalVolumeKg == 400)
        #expect(first.totalSets == 1)
        #expect(stats.bestWeight?.value == 80)
        #expect(stats.bestWeight?.date == first.startedAt)
        #expect(stats.workoutCount == 2)
    }

    @Test func editingLaterWorkoutGivesItRecords() async {
        await store.addWorkout(on: 1, squat.id, weightKg: 60)
        let second = await store.addWorkout(on: 3, squat.id, weightKg: 55)
        #expect(second.recordCount == 0)

        await store.edit(second, squat.id, weightKg: 62.5, sets: 2)

        #expect(second.recordCount > 0)
        #expect(second.totalSets == 2)
        #expect(second.totalVolumeKg == 625)
        #expect(stats.bestWeight?.value == 62.5)
    }

    @Test func movingWorkoutEarlierMovesRecords() async throws {
        let first = await store.addWorkout(on: 2, squat.id, weightKg: 70)
        let second = await store.addWorkout(on: 4, squat.id, weightKg: 60)
        #expect(first.recordCount == 0)
        #expect(second.recordCount == 0)

        // Same sets, an earlier day: the 70 kg workout now beats it.
        await store.edit(second, day: 1, squat.id, weightKg: 60)

        #expect(second.startedAt == TestStore.date(1))
        #expect(second.recordCount == 0)
        #expect(first.recordCount > 0)
        // The sets repeat the start time, so a moved workout's sets move with it.
        let sets = try store.context.fetch(FetchDescriptor<WorkoutSet>())
        #expect(Set(sets.map(\.workoutStartedAt)) == [TestStore.date(1), TestStore.date(2)])
        #expect(store.context.exerciseWorkouts(squat.id).map(\.workout.startedAt) == [TestStore.date(1), TestStore.date(2)])
    }

    @Test func deletingWorkoutGivesLaterOneRecords() async {
        await store.addWorkout(on: 1, squat.id, weightKg: 60)
        let heavy = await store.addWorkout(on: 2, squat.id, weightKg: 70)
        let third = await store.addWorkout(on: 3, squat.id, weightKg: 65)
        #expect(third.recordCount == 0)

        store.context.deleteWorkouts([heavy])
        await RecordRecount.finish()

        #expect(third.recordCount > 0)
        #expect(stats.workoutCount == 2)
        #expect(stats.bestWeight?.value == 65)
    }

    @Test func workoutsOnSameMinuteGetDistinctStarts() async {
        let first = await store.addWorkout(on: 1, squat.id, weightKg: 60)
        let second = await store.addWorkout(on: 1, squat.id, weightKg: 70)
        #expect(first.startedAt != second.startedAt)
        #expect(second.recordCount > 0)
    }

    @Test func editedTotalsReachSummary() async {
        let workout = await store.addWorkout(on: 1, squat.id, weightKg: 60, sets: 3)
        await store.edit(workout, squat.id, weightKg: 100, sets: 3)
        let summary = HistorySummary(workouts: [workout.facts(groups: [squat.id: squat.primaryGroup])],
                                     period: .month, now: TestStore.date(20), calendar: Calendar(identifier: .gregorian))
        #expect(summary.workoutCount == 1)
        #expect(summary.volumeKg == 1500)
        #expect(summary.setsByGroup.first?.sets == 3)
    }
}

/// The background reads give what the main context would (TECH T12).
@MainActor
struct HistoryReaderTests {
    @Test func readsAsMainContext() async throws {
        let store = try TestStore()
        let squat = store.exercise()
        let first = await store.addWorkout(on: 1, squat.id, weightKg: 60, sets: 2)
        await store.addWorkout(on: 3, squat.id, weightKg: 70, sets: 3)
        let container = store.container
        let id = squat.id

        let read = await HistoryReader.read(container) { await $0.exerciseHistory(id) }
        #expect(read.workouts.map(\.startedAt) == [TestStore.date(1), TestStore.date(3)])
        #expect(read.workouts.first?.workoutID == first.persistentModelID)
        #expect(read.workouts.last?.sets == Array(repeating: PlannedSet(reps: 5, weightKg: 70), count: 3))
        #expect(read.stats.bestWeight?.value == 70)

        let calendar = Calendar(identifier: .gregorian)
        let summary = await HistoryReader.read(container) {
            await $0.summary(period: .month, now: TestStore.date(20), calendar: calendar)
        }
        #expect(summary.workoutCount == 2)
        #expect(summary.volumeKg == 600 + 1050)
        #expect(summary.setsByGroup.first?.sets == 5)

        let history = await HistoryReader.read(container) { await $0.recordHistory(of: [id]) }
        #expect(history[squat.id]?.count == 2)
    }
}
