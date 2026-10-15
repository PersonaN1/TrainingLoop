import Foundation
import Testing
@testable import TrainingLoopCore

struct ExampleTemplatesTests {
    private let templates = ExampleTemplates.all(.init(fullBody: "A", legsAndPullUps: "B", homeNoEquipment: "C"))

    private func keys(_ definition: TemplateDefinition) -> [String] {
        let byID = Dictionary(uniqueKeysWithValues: BuiltinExercises.all.map { ($0.exerciseID, $0.key) })
        return definition.exerciseIDs.map { byID[$0] ?? "?" }
    }

    @Test func threeTemplatesInOrder() {
        #expect(templates.map(\.name) == ["A", "B", "C"])
    }

    @Test func fullBody() {
        #expect(keys(templates[0].definition)
            == ["barbell_back_squat", "barbell_bench_press", "barbell_row", "overhead_press", "plank"])
    }

    @Test func legsAndPullUpsSuperset() throws {
        let definition = templates[1].definition
        #expect(keys(definition) == ["barbell_back_squat", "pull_up", "romanian_deadlift"])
        guard case .superset(let superset) = definition.items.first else {
            Issue.record("Expected a superset first")
            return
        }
        #expect(superset.restWithinSeconds == 30)
        #expect(superset.restAfterSeconds == 90)
        #expect(superset.exercises.allSatisfy { $0.sets.count == 4 })
    }

    @Test func homeNoEquipment() {
        let definition = templates[2].definition
        #expect(keys(definition) == ["push_up", "air_squat", "crunch", "burpee", "plank"])
        guard case .superset(let superset) = definition.items.first else {
            Issue.record("Expected a superset first")
            return
        }
        #expect(superset.exercises.allSatisfy { $0.sets.count == 3 })
    }

    /// Without weights (D18), and sets match the exercise's measure.
    @Test func setsMatchMeasureAndHaveNoWeight() {
        let byID = Dictionary(uniqueKeysWithValues: BuiltinExercises.all.map { ($0.exerciseID, $0) })
        for template in templates {
            for exercise in template.definition.exercises {
                let measure = byID[exercise.exerciseID]?.measure
                for set in exercise.sets {
                    #expect(set.weightKg == nil)
                    #expect((set.reps != nil) == (measure == .reps))
                    #expect((set.seconds != nil) == (measure == .time))
                }
            }
        }
    }
}
