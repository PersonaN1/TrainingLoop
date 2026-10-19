/// The three example templates created on first launch instead of onboarding (SPEC D18).
/// No weights: the first workout fills them in, and "previous time" offers them afterwards.
public enum ExampleTemplates {
    /// Template names in the interface language, supplied by the app.
    public struct Names: Sendable {
        public var fullBody: String
        public var legsAndPullUps: String
        public var homeNoEquipment: String

        public init(fullBody: String, legsAndPullUps: String, homeNoEquipment: String) {
            self.fullBody = fullBody
            self.legsAndPullUps = legsAndPullUps
            self.homeNoEquipment = homeNoEquipment
        }
    }

    /// Each example with its key: the stored template keeps the key, so the copies two devices create
    /// on their first launch are found after iCloud sync (TECH T13).
    public static func all(_ names: Names) -> [(key: String, name: String, definition: TemplateDefinition)] {
        [
            ("fullBody", names.fullBody, TemplateDefinition(items: [
                .exercise(exercise("barbell_back_squat", sets: 3, reps: 8, rest: 120)),
                .exercise(exercise("barbell_bench_press", sets: 3, reps: 8, rest: 120)),
                .exercise(exercise("barbell_row", sets: 3, reps: 8, rest: 90)),
                .exercise(exercise("overhead_press", sets: 3, reps: 8, rest: 90)),
                .exercise(exercise("plank", sets: 3, seconds: 45, rest: 60)),
            ])),
            ("legsAndPullUps", names.legsAndPullUps, TemplateDefinition(items: [
                .superset(TemplateSuperset(
                    exercises: [
                        exercise("barbell_back_squat", sets: 4, reps: 8, rest: 90),
                        exercise("pull_up", sets: 4, reps: 6, rest: 90),
                    ],
                    restWithinSeconds: 30,
                    restAfterSeconds: 90
                )),
                .exercise(exercise("romanian_deadlift", sets: 3, reps: 10, rest: 90)),
            ])),
            ("homeNoEquipment", names.homeNoEquipment, TemplateDefinition(items: [
                .superset(TemplateSuperset(
                    exercises: [
                        exercise("push_up", sets: 3, reps: 15, rest: 60),
                        exercise("air_squat", sets: 3, reps: 20, rest: 60),
                        exercise("crunch", sets: 3, reps: 20, rest: 60),
                        exercise("burpee", sets: 3, reps: 10, rest: 60),
                    ],
                    restWithinSeconds: 15,
                    restAfterSeconds: 90
                )),
                .exercise(exercise("plank", sets: 3, seconds: 45, rest: 60)),
            ])),
        ]
    }

    private static func exercise(_ key: String, sets: Int, reps: Int? = nil, seconds: Int? = nil,
                                 rest: Int) -> TemplateExercise {
        guard let builtin = BuiltinExercises.exercise(key: key) else {
            preconditionFailure("Unknown built-in exercise \(key)")
        }
        return TemplateExercise(
            exerciseID: builtin.exerciseID,
            sets: Array(repeating: PlannedSet(reps: reps, seconds: seconds), count: sets),
            restSeconds: rest
        )
    }
}
