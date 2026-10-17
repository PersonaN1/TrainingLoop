import Foundation
import Testing
@testable import TrainingLoopCore

struct PersonalRecordsTests {
    private let bench = UUID()
    private let pullUp = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func workout(_ sets: [UUID: [PlannedSet]]) -> ActiveWorkout {
        var workout = ActiveWorkout(name: "Test", startedAt: start)
        for (id, values) in sets.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            var exercise = ActiveWorkout.newExercise(id, restSeconds: 60, previous: [], defaultSets: values.count)
            for index in values.indices {
                exercise.sets[index].entered = values[index]
                exercise.sets[index].doneAt = start.addingTimeInterval(Double(index) * 60)
            }
            workout.items.append(.exercise(exercise))
        }
        return workout
    }

    @Test func sameVolumeInAnotherOrderIsNoRecord() {
        // Pound weights: the same sums in another order differ in the last bits.
        let sets = [45.359237 * 1.5, 45.359237 * 2.25, 45.359237 * 3.75].map { PlannedSet(reps: 7, weightKg: $0) }
        var bests = PersonalBests(workouts: [sets.reversed()])
        let isRecord = bests.addVolume(PersonalBests.volume(of: sets))
        #expect(!isRecord)
    }

    @Test func firstTimeSetsNoRecords() {
        let records = workout([bench: [PlannedSet(reps: 5, weightKg: 100)]]).records(history: [:])
        #expect(records.setIDs.isEmpty)
        #expect(records.records.isEmpty)
    }

    @Test func heavierSetIsOneWeightLine() {
        let history = [bench: [[PlannedSet(reps: 5, weightKg: 90)]]]
        let workout = workout([bench: [PlannedSet(reps: 5, weightKg: 95), PlannedSet(reps: 5, weightKg: 100)]])
        let records = workout.records(history: history)
        // Both sets beat the weight at the time they were ticked; the list keeps the final one.
        #expect(records.setIDs.count == 2)
        #expect(records.records.map(\.metric) == [.weight, .volume])
        #expect(records.records[0].set == PlannedSet(reps: 5, weightKg: 100))
        #expect(records.records[1].volumeKg == 975)
    }

    @Test func repRecordShowsTheMostReps() {
        // Best ever 100 × 1; now 90 × 8 beats 3, 5 and 8 reps but not the weight, and the volume (720 > 700).
        let history = [bench: [[PlannedSet(reps: 1, weightKg: 100), PlannedSet(reps: 10, weightKg: 60)]]]
        let records = workout([bench: [PlannedSet(reps: 8, weightKg: 90)]]).records(history: history)
        #expect(records.records.map(\.metric) == [.weightForReps(8), .volume])
    }

    @Test func bodyweightCountsReps() {
        let history = [pullUp: [[PlannedSet(reps: 10)]]]
        let records = workout([pullUp: [PlannedSet(reps: 12)]]).records(history: history)
        #expect(records.records.map(\.metric) == [.reps])
    }

    @Test func historyRecordsMatchTheSummary() {
        // As on the summary: the first workout sets none, the second folds weight and its rep records.
        let records = PersonalBests.records(of: [
            [PlannedSet(reps: 5, weightKg: 80)],
            [PlannedSet(reps: 5, weightKg: 85), PlannedSet(reps: 3, weightKg: 70)],
            [PlannedSet(reps: 5, weightKg: 85)],
        ])
        #expect(records.map(\.lines.count) == [0, 2, 0])
        #expect(records[1].lines.map(\.metric) == [.weight, .volume])
        #expect(records[1].setIndices == [0])
    }

    @Test func historyRecordsCountEarlierWorkoutsOnly() {
        // A workout added before a better one: the earlier is the record, the later beats it.
        let early = [PlannedSet(reps: 10)]
        let late = [PlannedSet(reps: 12)]
        #expect(PersonalBests.records(of: [early, late]).map(\.lines.count) == [0, 1])
        #expect(PersonalBests.records(of: [late, early]).map(\.lines.count) == [0, 0])
    }

    @Test func firstWorkoutSetsNoRecordsEvenWhenItsSetsImprove() {
        let first = [PlannedSet(reps: 10, weightKg: 60), PlannedSet(reps: 5, weightKg: 70)]
        let second = [PlannedSet(reps: 3, weightKg: 75), PlannedSet(reps: 8, weightKg: 65)]
        let records = PersonalBests.records(of: [first, second])
        #expect(records[0].isEmpty)
        // 65 × 8 is the first set with 8 reps at more than 60: it beats weight for 8 reps.
        #expect(records[1].lines.map(\.metric) == [.weight, .weightForReps(8)])
    }
}
