import Foundation
import Testing
@testable import TrainingLoopCore

/// Sets recorded left and right separately (SPEC D23).
struct SidesTests {
    private let curl = UUID()

    private func row(planned: PlannedSet = PlannedSet(), previous: PlannedSet? = nil,
                     entered: PlannedSet = PlannedSet()) -> ActiveWorkout.SetRow {
        ActiveWorkout.SetRow(planned: planned, previous: previous, entered: entered, bySide: true)
    }

    @Test func sidesOfASet() {
        let set = PlannedSet(reps: 10, weightKg: 14, right: .init(reps: 9, weightKg: 12))
        #expect(set.sides == [PlannedSet(reps: 10, weightKg: 14), PlannedSet(reps: 9, weightKg: 12)])
        #expect(set.volumeKg == 248)
        #expect(PlannedSet(reps: 5, weightKg: 100).sides.count == 1)
    }

    @Test func templateValueIsForBothSides() {
        let set = row(planned: PlannedSet(reps: 10), previous: PlannedSet(reps: 8, weightKg: 14, right: .init(reps: 7, weightKg: 12)))
        #expect(set.suggested == PlannedSet(reps: 10, weightKg: 14, right: .init(reps: 10, weightKg: 12)))
    }

    @Test func lastTimeWithoutSidesSuggestsBoth() {
        let set = row(previous: PlannedSet(reps: 8, weightKg: 14))
        #expect(set.suggested.right == .init(reps: 8, weightKg: 14))
    }

    @Test func typedSideOverSuggestion() {
        var set = row(previous: PlannedSet(reps: 8, weightKg: 14))
        set.entered.right = .init(weightKg: 12)
        #expect(set.value == PlannedSet(reps: 8, weightKg: 14, right: .init(reps: 8, weightKg: 12)))
    }

    @Test func tickNeedsBothSides() {
        var set = row()
        set.entered.reps = 10
        #expect(!set.canTick(measure: .reps))
        set.entered.right = .init(reps: 9)
        #expect(set.canTick(measure: .reps))
    }

    @Test func setWithoutSidesHasNoRight() {
        let set = ActiveWorkout.SetRow(planned: PlannedSet(), previous: PlannedSet(reps: 8, right: .init(reps: 7)))
        #expect(set.value == PlannedSet(reps: 8))
    }

    @Test func fitSplitsOpenSetsOnly() {
        var workout = ActiveWorkout(name: "W", startedAt: .now, items: [
            .exercise(.init(exerciseID: curl, restSeconds: 60, sets: [
                .init(planned: PlannedSet(), previous: nil, entered: PlannedSet(reps: 10), doneAt: .now),
                .init(planned: PlannedSet(), previous: nil, entered: PlannedSet(reps: 10, right: .init(reps: 9))),
            ])),
        ])
        workout.fitSets { _ in .init(measure: .reps, weighted: true, bySide: true) }
        let sets = workout.items[0].exercises[0].sets
        #expect(!sets[0].bySide)
        #expect(sets[1].bySide)
        #expect(sets[1].entered.right == .init(reps: 9))

        workout.fitSets { _ in .init(measure: .reps, weighted: true, bySide: false) }
        #expect(workout.items[0].exercises[0].sets[1].entered.right == nil)
    }

    @Test func addedSetKeepsSides() {
        var workout = ActiveWorkout(name: "W", startedAt: .now, items: [
            .exercise(.init(exerciseID: curl, restSeconds: 60, sets: [
                row(entered: PlannedSet(reps: 10, weightKg: 14, right: .init(reps: 9, weightKg: 12))),
            ])),
        ])
        workout.addSet(to: workout.items[0].id)
        let added = workout.items[0].exercises[0].sets[1]
        #expect(added.bySide)
        #expect(added.value.right == .init(reps: 9, weightKg: 12))
    }

    @Test func templateTakesTheLeftSide() {
        let workout = ActiveWorkout(name: "W", startedAt: .now, items: [
            .exercise(.init(exerciseID: curl, restSeconds: 60, sets: [
                row(entered: PlannedSet(reps: 10, weightKg: 14, right: .init(reps: 9, weightKg: 12))),
            ])),
        ])
        #expect(workout.asTemplate.exercises[0].sets == [PlannedSet(reps: 10, weightKg: 14)])
    }

    /// A workout file from an earlier build has no `bySide`.
    @Test func decodesRowsWithoutSides() throws {
        let json = #"{"id":"\#(UUID().uuidString)","planned":{},"entered":{"reps":5}}"#
        let set = try JSONDecoder().decode(ActiveWorkout.SetRow.self, from: Data(json.utf8))
        #expect(!set.bySide)
        #expect(set.entered.reps == 5)
    }

    @Test func recordsTakeTheBetterSide() {
        var bests = PersonalBests(workouts: [[PlannedSet(reps: 10, weightKg: 12)]])
        let records = bests.take([PlannedSet(reps: 10, weightKg: 12, right: .init(reps: 10, weightKg: 14))])
        #expect(records.lines.map(\.metric).contains(.weight))
        #expect(bests.values[.weight] == 14)
        #expect(bests.values[.volume] == 260)
    }

    @Test func statsTakeTheBetterSideAndAddBoth() {
        let stats = ExerciseStats(sessions: [
            .init(date: .now, sets: [PlannedSet(reps: 10, weightKg: 12, right: .init(reps: 8, weightKg: 14))]),
        ])
        #expect(stats.bestWeight?.value == 14)
        #expect(stats.bestWeight?.set == PlannedSet(reps: 8, weightKg: 14))
        #expect(stats.points(.volume).first?.value == 232)
        #expect(stats.points(.totalReps).first?.value == 18)
        #expect(stats.points(.maxReps).first?.value == 10)
    }
}
