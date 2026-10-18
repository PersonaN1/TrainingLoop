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
        for language in ["en", "ru"] {
            let names = all.map { $0.name(languageCode: language) }
            #expect(Set(names).count == all.count, "\(language)")
        }
    }

    /// Every key has a name in every language; a missing one would show the raw key.
    @Test func everyNameIsTranslated() {
        for exercise in all {
            for language in ["en", "ru"] {
                let name = exercise.name(languageCode: language)
                #expect(!name.isEmpty && name != exercise.key, "\(exercise.key) in \(language)")
            }
        }
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
        #expect(BuiltinExercises.exercise(key: "farmers_walk")?.name(languageCode: "ru") == "Фермерская прогулка")
        #expect(BuiltinExercises.exercise(key: "missing") == nil)
    }

    /// "Other" is for the user's own exercises that fit no group.
    @Test func everyMuscleGroupIsCovered() {
        #expect(Set(all.map(\.primaryGroup)) == Set(MuscleGroup.allCases).subtracting([.other]))
    }

    @Test func oldLegGroupsReadAsLegs() {
        for raw in ["quads", "hamstrings", "glutes", "calves"] {
            #expect(MuscleGroup(storedRawValue: raw) == .legs)
        }
        #expect(MuscleGroup(storedRawValue: "chest") == .chest)
        #expect(MuscleGroup(storedRawValue: "unknown") == nil)
    }

    @Test func cableReadsAsMachine() {
        #expect(Equipment(storedRawValue: "cable") == .machine)
        #expect(Equipment(storedRawValue: "band") == .band)
        #expect(!all.contains { $0.equipment.rawValue == "cable" })
    }
}
