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

    @Test func editingEarlierWorkoutTakesLaterRecordsAway() {
        let first = store.addWorkout(on: 1, squat.id, weightKg: 60)
        let second = store.addWorkout(on: 3, squat.id, weightKg: 70)
        #expect(first.recordCount == 0)
        #expect(second.recordCount > 0)

        // The first workout was actually heavier: the second one beats nothing now.
        store.edit(first, squat.id, weightKg: 80)

        #expect(first.recordCount == 0)
        #expect(second.recordCount == 0)
        #expect(first.totalVolumeKg == 400)
        #expect(first.totalSets == 1)
        #expect(stats.bestWeight?.value == 80)
        #expect(stats.bestWeight?.date == first.startedAt)
        #expect(stats.workoutCount == 2)
    }

    @Test func editingLaterWorkoutGivesItRecords() {
        store.addWorkout(on: 1, squat.id, weightKg: 60)
        let second = store.addWorkout(on: 3, squat.id, weightKg: 55)
        #expect(second.recordCount == 0)

        store.edit(second, squat.id, weightKg: 62.5, sets: 2)

        #expect(second.recordCount > 0)
        #expect(second.totalSets == 2)
        #expect(second.totalVolumeKg == 625)
        #expect(stats.bestWeight?.value == 62.5)
    }

    @Test func movingWorkoutEarlierMovesRecords() throws {
        let first = store.addWorkout(on: 2, squat.id, weightKg: 70)
        let second = store.addWorkout(on: 4, squat.id, weightKg: 60)
        #expect(first.recordCount == 0)
        #expect(second.recordCount == 0)

        // Same sets, an earlier day: the 70 kg workout now beats it.
        store.edit(second, day: 1, squat.id, weightKg: 60)

        #expect(second.startedAt == TestStore.date(1))
        #expect(second.recordCount == 0)
        #expect(first.recordCount > 0)
        // The sets repeat the start time, so a moved workout's sets move with it.
        let sets = try store.context.fetch(FetchDescriptor<WorkoutSet>())
        #expect(Set(sets.map(\.workoutStartedAt)) == [TestStore.date(1), TestStore.date(2)])
        #expect(store.context.exerciseWorkouts(squat.id).map(\.workout.startedAt) == [TestStore.date(1), TestStore.date(2)])
    }

    @Test func deletingWorkoutGivesLaterOneRecords() {
        store.addWorkout(on: 1, squat.id, weightKg: 60)
        let heavy = store.addWorkout(on: 2, squat.id, weightKg: 70)
        let third = store.addWorkout(on: 3, squat.id, weightKg: 65)
        #expect(third.recordCount == 0)

        store.context.deleteWorkouts([heavy])

        #expect(third.recordCount > 0)
        #expect(stats.workoutCount == 2)
        #expect(stats.bestWeight?.value == 65)
    }

    @Test func workoutsOnSameMinuteGetDistinctStarts() {
        let first = store.addWorkout(on: 1, squat.id, weightKg: 60)
        let second = store.addWorkout(on: 1, squat.id, weightKg: 70)
        #expect(first.startedAt != second.startedAt)
        #expect(second.recordCount > 0)
    }

    @Test func editedTotalsReachSummary() {
        let workout = store.addWorkout(on: 1, squat.id, weightKg: 60, sets: 3)
        store.edit(workout, squat.id, weightKg: 100, sets: 3)
        let summary = HistorySummary(workouts: [workout.facts(groups: [squat.id: squat.primaryGroup])],
                                     period: .month, now: TestStore.date(20), calendar: Calendar(identifier: .gregorian))
        #expect(summary.workoutCount == 1)
        #expect(summary.volumeKg == 1500)
        #expect(summary.setsByGroup.first?.sets == 3)
    }
}
