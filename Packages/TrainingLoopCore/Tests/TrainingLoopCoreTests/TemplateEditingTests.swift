import Foundation
import Testing
@testable import TrainingLoopCore

struct TemplateEditingTests {
    private let squat = UUID()
    private let pullUp = UUID()
    private let deadlift = UUID()

    private func plain(_ exerciseID: UUID, sets: Int = 3, reps: Int = 10, rest: Int = 90) -> TemplateExercise {
        TemplateExercise(exerciseID: exerciseID, sets: Array(repeating: PlannedSet(reps: reps), count: sets),
                         restSeconds: rest)
    }

    @Test func mergeNeighboursIntoSuperset() throws {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        var definition = TemplateDefinition(items: [.exercise(a), .exercise(b), .exercise(c)])
        try definition.mergeIntoSuperset(itemIDs: [a.id, b.id], restWithinSeconds: 30, restAfterSeconds: 90)
        #expect(definition.items.count == 2)
        guard case .superset(let superset) = definition.items[0] else { Issue.record("no superset"); return }
        #expect(superset.exercises.map(\.id) == [a.id, b.id])
        #expect(superset.restWithinSeconds == 30)
        #expect(definition.exerciseIDs == [squat, pullUp, deadlift])
    }

    @Test func mergeRejectsGapsSingleItemsAndWholeSupersets() throws {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        var definition = TemplateDefinition(items: [.exercise(a), .exercise(b), .exercise(c)])
        #expect(throws: TemplateDefinition.MergeError.notContiguous) {
            try definition.mergeIntoSuperset(itemIDs: [a.id, c.id], restWithinSeconds: 0, restAfterSeconds: 0)
        }
        #expect(throws: TemplateDefinition.MergeError.notContiguous) {
            try definition.mergeIntoSuperset(itemIDs: [a.id], restWithinSeconds: 0, restAfterSeconds: 0)
        }
        try definition.mergeIntoSuperset(itemIDs: [a.id, b.id], restWithinSeconds: 0, restAfterSeconds: 0)
        let supersetID = definition.items[0].id
        #expect(throws: TemplateDefinition.MergeError.alreadySuperset) {
            try definition.mergeIntoSuperset(itemIDs: [supersetID], restWithinSeconds: 0, restAfterSeconds: 0)
        }
    }

    @Test func mergeAddsToAnExistingSupersetKeepingItsRests() throws {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b], restWithinSeconds: 15, restAfterSeconds: 120)
        var definition = TemplateDefinition(items: [.superset(superset), .exercise(c)])
        try definition.mergeIntoSuperset(itemIDs: [superset.id, c.id], restWithinSeconds: 30, restAfterSeconds: 90)
        #expect(definition.items.count == 1)
        guard case .superset(let merged) = definition.items[0] else { Issue.record("no superset"); return }
        #expect(merged.id == superset.id)
        #expect(merged.exercises.count == 3)
        #expect(merged.restAfterSeconds == 120)
    }

    @Test func mergeBySelectedExercisesTakesWholeSupersets() throws {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b], restWithinSeconds: 15, restAfterSeconds: 120)
        var definition = TemplateDefinition(items: [.superset(superset), .exercise(c)])
        #expect(throws: TemplateDefinition.MergeError.alreadySuperset) {
            try definition.mergeIntoSuperset(exerciseIDs: [a.id, b.id], restWithinSeconds: 0, restAfterSeconds: 0)
        }
        try definition.mergeIntoSuperset(exerciseIDs: [b.id, c.id], restWithinSeconds: 30, restAfterSeconds: 90)
        #expect(definition.items.count == 1)
        #expect(definition.exercises.map(\.id) == [a.id, b.id, c.id])
        #expect(definition.supersetID(containing: c.id) == superset.id)
    }

    @Test func appendToSuperset() {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b], restWithinSeconds: 15, restAfterSeconds: 120)
        var definition = TemplateDefinition(items: [.superset(superset)])
        definition.appendExercises([c], toSuperset: superset.id)
        #expect(definition.items.count == 1)
        #expect(definition.exercises.map(\.id) == [a.id, b.id, c.id])
    }

    @Test func dragReordersInsideASuperset() {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b], restWithinSeconds: 15, restAfterSeconds: 120)
        var definition = TemplateDefinition(items: [.superset(superset), .exercise(c)])
        definition.moveExercises(fromOffsets: [1], toOffset: 0)
        guard case .superset(let moved) = definition.items[0] else { Issue.record("no superset"); return }
        #expect(moved.id == superset.id)
        #expect(moved.exercises.map(\.id) == [b.id, a.id])
        #expect(moved.restAfterSeconds == 120)
        #expect(definition.items[1] == .exercise(c))
    }

    @Test func dragOutOfAndIntoASuperset() {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b], restWithinSeconds: 15, restAfterSeconds: 120)
        var out = TemplateDefinition(items: [.superset(superset), .exercise(c)])
        out.moveExercises(fromOffsets: [1], toOffset: 3)
        #expect(out.items == [.exercise(a), .exercise(c), .exercise(b)])

        var into = TemplateDefinition(items: [.superset(superset), .exercise(c)])
        into.moveExercises(fromOffsets: [2], toOffset: 1)
        #expect(into.items.count == 1)
        #expect(into.exercises.map(\.id) == [a.id, c.id, b.id])

        // Next to a superset but not inside it: stays plain.
        var beside = TemplateDefinition(items: [.exercise(c), .superset(superset)])
        beside.moveExercises(fromOffsets: [0], toOffset: 3)
        #expect(beside.items == [.superset(superset), .exercise(c)])
    }

    @Test func takeOutGoesRightAfterTheSuperset() {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b, c], restWithinSeconds: 15, restAfterSeconds: 120)
        var definition = TemplateDefinition(items: [.superset(superset)])
        definition.takeOutOfSuperset(a.id)
        #expect(definition.items.count == 2)
        #expect(definition.exercises.map(\.id) == [b.id, c.id, a.id])
        definition.takeOutOfSuperset(b.id)
        #expect(definition.items == [.exercise(c), .exercise(b), .exercise(a)])
    }

    @Test func splitAndRemoveUnwrapSupersets() {
        let a = plain(squat), b = plain(pullUp), c = plain(deadlift)
        let superset = TemplateSuperset(exercises: [a, b, c], restWithinSeconds: 15, restAfterSeconds: 90)
        var definition = TemplateDefinition(items: [.superset(superset)])
        definition.removeExercise(c.id)
        definition.removeExercise(b.id)
        #expect(definition.items == [.exercise(a)])

        var other = TemplateDefinition(items: [.superset(superset)])
        other.splitSuperset(superset.id)
        #expect(other.items == [.exercise(a), .exercise(b), .exercise(c)])
    }

    @Test func duplicateStaysInsideTheSuperset() {
        let a = plain(squat), b = plain(pullUp)
        let superset = TemplateSuperset(exercises: [a, b], restWithinSeconds: 15, restAfterSeconds: 90)
        var definition = TemplateDefinition(items: [.superset(superset)])
        definition.duplicateExercise(a.id)
        #expect(definition.items.count == 1)
        #expect(definition.exerciseIDs == [squat, squat, pullUp])
        #expect(Set(definition.exercises.map(\.id)).count == 3)
    }

    @Test func replaceConvertsSetsToTheNewType() {
        var set = PlannedSet(reps: 8, weightKg: 20)
        let a = TemplateExercise(exerciseID: squat, sets: [set, set], restSeconds: 60)
        var definition = TemplateDefinition(items: [.exercise(a)])
        definition.replaceExercise(a.id, with: pullUp, measure: .time)
        set = PlannedSet(seconds: 45, weightKg: 20)
        #expect(definition.exercises[0].exerciseID == pullUp)
        #expect(definition.exercises[0].sets == [set, set])
    }

    @Test func estimateCountsSetsAndRestsButNotTheLastRest() {
        // 3 sets × 40 s + 3 × 60 s rest − last 60 s = 240 s.
        let single = TemplateDefinition(items: [.exercise(plain(squat, rest: 60))])
        #expect(single.estimatedSeconds == 240)
        #expect(single.estimatedMinutes == 4)

        // Rounds: 4, 4, 2 sets → (2 + 2 + 1 + 1) × 40 = 240; within: 1+1+0+0 → 30 s; after: 4 × 90 − last 90.
        let superset = TemplateSuperset(exercises: [plain(squat, sets: 4), plain(pullUp, sets: 2)],
                                        restWithinSeconds: 15, restAfterSeconds: 90)
        let definition = TemplateDefinition(items: [.superset(superset)])
        #expect(definition.setCount == 6)
        #expect(definition.estimatedSeconds == 6 * 40 + 2 * 15 + 3 * 90)
        #expect(TemplateDefinition().estimatedMinutes == nil)
    }

    @Test func setsSummaryShowsRanges() {
        #expect(SetsSummary([PlannedSet(reps: 8), PlannedSet(reps: 8)]).value == .reps(8...8))
        #expect(SetsSummary([PlannedSet(reps: 12), PlannedSet(reps: 10)]).value == .reps(10...12))
        #expect(SetsSummary([PlannedSet(seconds: 45)]).value == .seconds(45...45))
        #expect(SetsSummary([PlannedSet()]).value == nil)
    }

    @Test func uniqueTemplateNames() {
        #expect(TemplateNaming.unique("New Workout", among: ["Legs"]) == "New Workout")
        #expect(TemplateNaming.unique("New Workout", among: ["new workout", "New Workout 2"]) == "New Workout 3")
    }

    @Test func weightInputRoundsToQuarterAndCaps() {
        #expect(WeightInput.kilograms(from: "62,6", unit: .kg) == 62.5)
        #expect(WeightInput.kilograms(from: " ", unit: .kg) == nil)
        #expect(WeightInput.kilograms(from: "abc", unit: .kg) == nil)
        #expect(WeightInput.kilograms(from: "5000", unit: .kg) == 999.75)
        let pounds = WeightInput.kilograms(from: "135", unit: .lb)!
        #expect(WeightInput.displayValue(pounds, unit: .lb) == 135)
    }
}
