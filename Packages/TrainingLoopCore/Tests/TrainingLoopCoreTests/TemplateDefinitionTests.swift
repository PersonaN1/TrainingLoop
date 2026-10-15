import Foundation
import Testing
@testable import TrainingLoopCore

struct TemplateDefinitionTests {
    private let squat = UUID()
    private let pullUp = UUID()
    private let deadlift = UUID()

    private let example: TemplateDefinition

    init() {
        example = TemplateDefinition(items: [
            .superset(TemplateSuperset(
                exercises: [
                    TemplateExercise(exerciseID: squat, sets: [PlannedSet(reps: 8, weightKg: 62.5)], restSeconds: 90),
                    TemplateExercise(exerciseID: pullUp, sets: [PlannedSet(reps: 6)], restSeconds: 90),
                ],
                restWithinSeconds: 30,
                restAfterSeconds: 90
            )),
            .exercise(TemplateExercise(exerciseID: deadlift, sets: [PlannedSet(reps: 5), PlannedSet(reps: 5)], restSeconds: 120)),
        ])
    }

    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(example)
        #expect(try JSONDecoder().decode(TemplateDefinition.self, from: data) == example)
    }

    @Test func listsExercisesInOrderIncludingSupersetMembers() {
        #expect(example.exerciseIDs == [squat, pullUp, deadlift])
    }

    /// The stored format must stay readable after refactors: decode a literal, not just our own output.
    @Test func decodesStoredFormat() throws {
        let json = """
        {"items":[
          {"kind":"exercise","exercise":{"id":"00000000-0000-0000-0000-000000000001",
            "exerciseID":"00000000-0000-0000-0000-0000000000AA",
            "sets":[{"seconds":60},{"reps":10,"weightKg":20.5}],"restSeconds":60}},
          {"kind":"superset","superset":{"id":"00000000-0000-0000-0000-000000000002",
            "exercises":[],"restWithinSeconds":30,"restAfterSeconds":90}}
        ]}
        """
        let definition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(json.utf8))
        guard case .exercise(let exercise) = definition.items[0],
              case .superset(let superset) = definition.items[1] else {
            Issue.record("Unexpected items: \(definition.items)")
            return
        }
        #expect(exercise.sets == [PlannedSet(seconds: 60), PlannedSet(reps: 10, weightKg: 20.5)])
        #expect(exercise.restSeconds == 60)
        #expect(superset.restWithinSeconds == 30)
        #expect(superset.restAfterSeconds == 90)
    }
}
