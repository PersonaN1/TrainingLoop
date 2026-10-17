import Foundation
import Testing
@testable import TrainingLoopCore

struct ExerciseNameTests {
    @Test func cleanedTrimsAndCollapsesSpaces() {
        #expect(ExerciseName.cleaned("  Жим   лёжа \n") == "Жим лёжа")
        #expect(ExerciseName.cleaned(String(repeating: "a", count: 70)).count == 60)
    }

    @Test func emptyNameIsRejected() {
        #expect(ExerciseName.problem("   ", otherNames: []) == .empty)
    }

    @Test func duplicatesIgnoreCaseDiacriticsAndSpacing() {
        let others = ["Жим лёжа", "Pull-up"]
        #expect(ExerciseName.problem(" жим  лежа", otherNames: others) == .duplicate)
        #expect(ExerciseName.problem("PULL-UP", otherNames: others) == .duplicate)
        #expect(ExerciseName.problem("Жим стоя", otherNames: others) == nil)
    }

    @Test func copyNameFindsAFreeNumber() {
        #expect(ExerciseName.copyName(of: "Присед", otherNames: ["Присед"]) == "Присед (2)")
        #expect(ExerciseName.copyName(of: "Присед", otherNames: ["Присед", "присед (2)"]) == "Присед (3)")
        let long = String(repeating: "x", count: 60)
        let copy = ExerciseName.copyName(of: long, otherNames: [long])
        #expect(copy.count == 60)
        #expect(copy.hasSuffix(" (2)"))
    }
}

struct ExerciseFilterTests {
    @Test func emptyFilterMatchesEverything() {
        let filter = ExerciseFilter()
        #expect(!filter.isActive)
        #expect(filter.matches(primaryGroup: .back, equipment: .barbell, isCustom: false))
    }

    @Test func conditionsCombine() {
        let filter = ExerciseFilter(group: .back, equipment: .machine, onlyCustom: true)
        #expect(filter.activeCount == 3)
        #expect(filter.matches(primaryGroup: .back, equipment: .machine, isCustom: true))
        #expect(!filter.matches(primaryGroup: .back, equipment: .machine, isCustom: false))
        #expect(!filter.matches(primaryGroup: .chest, equipment: .machine, isCustom: true))
        #expect(!filter.matches(primaryGroup: .back, equipment: .band, isCustom: true))
    }

    @Test func onlyDoneKeepsExercisesWithWorkouts() {
        let filter = ExerciseFilter(onlyDone: true)
        #expect(filter.activeCount == 1)
        #expect(filter.matches(primaryGroup: .chest, equipment: .barbell, isCustom: false, isDone: true))
        #expect(!filter.matches(primaryGroup: .chest, equipment: .barbell, isCustom: false, isDone: false))
    }
}

struct ExerciseSearchTests {
    @Test func everyWordMustMatch() {
        #expect(ExerciseSearch.matches("тяга накл", names: ["Тяга штанги в наклоне"]))
        #expect(!ExerciseSearch.matches("тяга блок", names: ["Тяга штанги в наклоне"]))
        #expect(ExerciseSearch.matches("  ", names: ["Anything"]))
    }

    @Test func matchesAnyLanguageAndIgnoresYo() {
        let names = ["Жим лёжа", "Bench Press"]
        #expect(ExerciseSearch.matches("bench", names: names))
        #expect(ExerciseSearch.matches("лежа", names: names))
    }
}

struct ExerciseSummaryTests {
    private let day1 = Date(timeIntervalSince1970: 0)
    private let day2 = Date(timeIntervalSince1970: 86_400)

    @Test func weightedBestIsHeaviestThenMostReps() {
        let summary = ExerciseSummary(sets: [
            PerformedSet(reps: 10, weightKg: 60, workoutStartedAt: day1),
            PerformedSet(reps: 5, weightKg: 80, workoutStartedAt: day1),
            PerformedSet(reps: 6, weightKg: 80, workoutStartedAt: day2),
        ], measure: .reps)
        #expect(summary.workoutCount == 2)
        #expect(summary.best == .weight(kg: 80, reps: 6))
    }

    @Test func withoutWeightBestIsMostReps() {
        let summary = ExerciseSummary(sets: [
            PerformedSet(reps: 20, workoutStartedAt: day1),
            PerformedSet(reps: 25, weightKg: 0, workoutStartedAt: day1),
        ], measure: .reps)
        #expect(summary.best == .reps(25))
    }

    @Test func timedBestIsLongest() {
        let summary = ExerciseSummary(sets: [
            PerformedSet(seconds: 45, workoutStartedAt: day1),
            PerformedSet(seconds: 60, workoutStartedAt: day1),
        ], measure: .time)
        #expect(summary.best == .seconds(60))
    }

    @Test func noSetsMeansNotDoneYet() {
        let summary = ExerciseSummary(sets: [], measure: .reps)
        #expect(summary.workoutCount == 0)
        #expect(summary.best == nil)
    }
}
