import Testing
@testable import TrainingLoopCore

struct BuiltinExercisesTests {
    private let all = BuiltinExercises.all

    @Test func matchesApprovedList() {
        #expect(all.count == 53)
    }

    @Test func keysAreUniqueSnakeCase() {
        #expect(Set(all.map(\.key)).count == all.count)
        for exercise in all {
            #expect(exercise.key.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }, "\(exercise.key)")
        }
    }

    /// Exercise names are unique (SPEC D8) in every language.
    @Test func namesAreUniquePerLanguage() {
        #expect(Set(all.map(\.nameEN)).count == all.count)
        #expect(Set(all.map(\.nameRU)).count == all.count)
    }

    @Test func timedExercises() {
        let timed = all.filter { $0.measure == .time }.map(\.key)
        #expect(timed == ["plank", "side_plank", "dead_hang", "farmers_walk"])
    }

    @Test func unweightedExercises() {
        let unweighted = all.filter { !$0.weighted }.map(\.key)
        #expect(unweighted == ["air_squat", "ab_wheel_rollout", "burpee"])
    }

    @Test func looksUpByKeyAndLanguage() throws {
        let pullUp = try #require(BuiltinExercises.exercise(key: "pull_up"))
        #expect(pullUp.primaryGroup == .back)
        #expect(pullUp.equipment == .bodyweight)
        #expect(pullUp.name(languageCode: "ru") == "Подтягивания")
        #expect(pullUp.name(languageCode: "en") == "Pull-up")
        #expect(pullUp.name(languageCode: "de") == "Pull-up")
        #expect(BuiltinExercises.exercise(key: "missing") == nil)
    }

    @Test func everyMuscleGroupIsCovered() {
        #expect(Set(all.map(\.primaryGroup)) == Set(MuscleGroup.allCases))
    }
}
