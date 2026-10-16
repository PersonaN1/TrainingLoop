import Foundation
import Testing
@testable import TrainingLoopCore

struct ActiveWorkoutTests {
    private let squat = UUID()
    private let pullUp = UUID()
    private let deadlift = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// Squat 4×8 ↔ pull-ups 3×6 in a superset (30 s / 90 s), then deadlift 2×10 with 120 s rest.
    private var template: TemplateDefinition {
        TemplateDefinition(items: [
            .superset(TemplateSuperset(exercises: [
                TemplateExercise(exerciseID: squat, sets: Array(repeating: PlannedSet(reps: 8, weightKg: 60), count: 4),
                                 restSeconds: 0),
                TemplateExercise(exerciseID: pullUp, sets: Array(repeating: PlannedSet(reps: 6), count: 3),
                                 restSeconds: 0),
            ], restWithinSeconds: 30, restAfterSeconds: 90)),
            .exercise(TemplateExercise(exerciseID: deadlift, sets: [PlannedSet(reps: 10), PlannedSet(reps: 10)],
                                       restSeconds: 120)),
        ])
    }

    private func workout(previous: [UUID: [PlannedSet]] = [:]) -> ActiveWorkout {
        ActiveWorkout(template: template, name: "Legs", templateID: UUID(), startedAt: start, previous: previous)
    }

    @Test func supersetGoesInRoundsAndLastRoundSkipsFinishedExercises() {
        let order = workout().order.map { [$0.item, $0.exercise, $0.set] }
        #expect(order == [
            [0, 0, 0], [0, 1, 0], [0, 0, 1], [0, 1, 1], [0, 0, 2], [0, 1, 2], [0, 0, 3],
            [1, 0, 0], [1, 0, 1],
        ])
    }

    @Test func restInsideAndAfterTheRound() {
        let workout = workout()
        #expect(workout.restSeconds(after: .init(item: 0, exercise: 0, set: 0)) == 30)
        #expect(workout.restSeconds(after: .init(item: 0, exercise: 1, set: 0)) == 90)
        // The fourth round has only the squat: it ends the round.
        #expect(workout.restSeconds(after: .init(item: 0, exercise: 0, set: 3)) == 90)
        #expect(workout.restSeconds(after: .init(item: 1, exercise: 0, set: 0)) == 120)
    }

    @Test func valuesComeFromTemplateThenLastTimeThenTyped() {
        var workout = workout(previous: [pullUp: [PlannedSet(reps: 7, weightKg: 10)]])
        let first = workout.items[0].exercises[1].sets[0]
        #expect(first.previous == PlannedSet(reps: 7, weightKg: 10))
        // Template reps win; the weight the template leaves empty comes from last time.
        #expect(first.value == PlannedSet(reps: 6, weightKg: 10))
        #expect(workout.items[0].exercises[1].sets[1].previous == nil)
        workout.updateSet(first.id) { $0.entered.reps = 5 }
        #expect(workout[workout.position(of: first.id)!].value == PlannedSet(reps: 5, weightKg: 10))
    }

    @Test func nextSetFollowsTheTicks() {
        var workout = workout()
        let first = workout[workout.nextPosition!]
        workout.updateSet(first.id) { $0.doneAt = start }
        #expect(workout.nextPosition == .init(item: 0, exercise: 1, set: 0))
        #expect(workout.doneSetCount == 1)
        #expect(workout.setCount == 9)
    }

    @Test func onlyTickedSetsAreKept() {
        var workout = workout()
        let squatSet = workout.items[0].exercises[0].sets[0].id
        let deadliftSet = workout.items[1].exercises[0].sets[1].id
        workout.updateSet(squatSet) { $0.doneAt = start.addingTimeInterval(60) }
        workout.updateSet(deadliftSet) { $0.doneAt = start.addingTimeInterval(600) }
        let done = workout.doneItems
        // The superset lost its pull-ups, so the squat stands alone.
        #expect(done.count == 2)
        #expect(!done[0].isSuperset)
        #expect(done.flatMap(\.exercises).map(\.sets.count) == [1, 1])
        #expect(workout.lastMarkAt == start.addingTimeInterval(600))
    }

    @Test func addRemoveAndCompositionChange() {
        var workout = workout()
        #expect(!workout.compositionDiffers(from: template))
        let deadliftID = workout.items[1].exercises[0].id
        workout.addSet(to: deadliftID)
        #expect(workout.items[1].exercises[0].sets.count == 3)
        #expect(workout.compositionDiffers(from: template))
        // Changed values alone don't count.
        var edited = self.workout()
        edited.updateSet(edited.items[1].exercises[0].sets[0].id) { $0.entered.reps = 12 }
        #expect(!edited.compositionDiffers(from: template))

        let pullUpID = workout.items[0].exercises[1].id
        workout.removeExercise(pullUpID)
        guard case .exercise(let squatAlone) = workout.items[0] else {
            Issue.record("A superset of one should become a plain exercise")
            return
        }
        #expect(squatAlone.restSeconds == 90)
    }

    @Test func asTemplateKeepsPlannedValuesAndAddedSets() {
        var workout = workout()
        workout.items.append(.exercise(ActiveWorkout.newExercise(UUID(), restSeconds: 60, previous: [])))
        let added = workout.items[2].exercises[0]
        workout.updateSet(added.sets[0].id) { $0.entered = PlannedSet(reps: 12, weightKg: 20) }
        workout.updateSet(workout.items[1].exercises[0].sets[0].id) { $0.entered.reps = 15 }
        let definition = workout.asTemplate
        #expect(definition.items.count == 3)
        #expect(definition.exercises[2].sets[0] == PlannedSet(reps: 10))
        #expect(definition.exercises[3].sets[0] == PlannedSet(reps: 12, weightKg: 20))
        #expect(definition.exercises[3].sets.count == 3)
    }

    @Test func survivesJSON() throws {
        var workout = workout()
        workout.rest = .init(endsAt: start.addingTimeInterval(90), totalSeconds: 90)
        let data = try JSONEncoder().encode(workout)
        #expect(try JSONDecoder().decode(ActiveWorkout.self, from: data) == workout)
    }
}
