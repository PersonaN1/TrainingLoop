import Foundation

/// An exercise shipped with the app (SPEC D8, D17). Name, measure and weighting are fixed;
/// the stored `Exercise` row refers to it by `key`. Names live in the `Exercises` String Catalog
/// under the same key, translated like any other interface text (TECH T10).
public struct BuiltinExercise: Hashable, Sendable, Identifiable {
    /// Stable identifier; never changes once shipped, even if a name does.
    public let key: String
    public let primaryGroup: MuscleGroup
    public let equipment: Equipment
    public let measure: Measure
    public let weighted: Bool

    public var id: String { key }

    /// `Exercise.id` of the stored row: derived from the key, so templates and synced devices
    /// refer to the same built-in exercise by the same ID.
    public var exerciseID: UUID { .stable(key, namespace: BuiltinExercises.namespace) }

    /// The name in the current interface language.
    public var name: String {
        Bundle.module.localizedString(forKey: key, value: nil, table: BuiltinExercises.table)
    }

    /// The name in the given language; the development language (English) for one without a translation.
    public func name(languageCode: String) -> String {
        let bundle = Bundle.module.path(forResource: languageCode, ofType: "lproj").flatMap(Bundle.init(path:))
            ?? Bundle.module.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
            ?? Bundle.module
        return bundle.localizedString(forKey: key, value: nil, table: BuiltinExercises.table)
    }
}

/// The built-in catalog, as approved in docs/EXERCISES.md. Missing rows are created at launch,
/// so new built-in exercises arrive with app updates (TECH T2).
public enum BuiltinExercises {
    /// Never change: every built-in exercise ID derives from it.
    static let namespace = UUID(uuidString: "E033B3B6-6439-49E8-88E7-5CBA7DB2C482")!
    /// String Catalog with the names: Exercises.xcstrings.
    static let table = "Exercises"

    public static func exercise(key: String) -> BuiltinExercise? {
        byKey[key]
    }

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    public static let all: [BuiltinExercise] = [
        BuiltinExercise(key: "barbell_back_squat", primaryGroup: .quads, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "front_squat", primaryGroup: .quads, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_press", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_lunge", primaryGroup: .quads, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "bulgarian_split_squat", primaryGroup: .quads, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_extension", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_squat", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "hack_squat", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "goblet_squat", primaryGroup: .quads, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "air_squat", primaryGroup: .quads, equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "romanian_deadlift", primaryGroup: .hamstrings, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_curl", primaryGroup: .hamstrings, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_hip_thrust", primaryGroup: .glutes, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "standing_calf_raise", primaryGroup: .calves, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_calf_raise", primaryGroup: .calves, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "deadlift", primaryGroup: .back, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "pull_up", primaryGroup: .back, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_row", primaryGroup: .back, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "one_arm_dumbbell_row", primaryGroup: .back, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "lat_pulldown", primaryGroup: .back, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_cable_row", primaryGroup: .back, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "back_extension", primaryGroup: .back, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "chin_up", primaryGroup: .back, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "t_bar_row", primaryGroup: .back, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_shrug", primaryGroup: .traps, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_bench_press", primaryGroup: .chest, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_bench_press", primaryGroup: .chest, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_bench_press", primaryGroup: .chest, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_fly", primaryGroup: .chest, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "cable_crossover", primaryGroup: .chest, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "push_up", primaryGroup: .chest, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_dumbbell_press", primaryGroup: .chest, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "overhead_press", primaryGroup: .shoulders, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_dumbbell_press", primaryGroup: .shoulders, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "lateral_raise", primaryGroup: .shoulders, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "rear_delt_fly", primaryGroup: .shoulders, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_curl", primaryGroup: .biceps, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "hammer_curl", primaryGroup: .biceps, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_curl", primaryGroup: .biceps, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dip", primaryGroup: .triceps, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "skull_crusher", primaryGroup: .triceps, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "triceps_pushdown", primaryGroup: .triceps, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "close_grip_bench_press", primaryGroup: .triceps, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "crunch", primaryGroup: .abs, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "hanging_leg_raise", primaryGroup: .abs, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "plank", primaryGroup: .abs, equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "side_plank", primaryGroup: .abs, equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "ab_wheel_rollout", primaryGroup: .abs, equipment: .other, measure: .reps, weighted: false),
        BuiltinExercise(key: "dead_hang", primaryGroup: .forearms, equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "weighted_neck_flexion", primaryGroup: .neck, equipment: .other, measure: .reps, weighted: true),
        BuiltinExercise(key: "kettlebell_swing", primaryGroup: .fullBody, equipment: .kettlebell, measure: .reps, weighted: true),
        BuiltinExercise(key: "burpee", primaryGroup: .fullBody, equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "farmers_walk", primaryGroup: .fullBody, equipment: .dumbbell, measure: .time, weighted: true),
    ]
}
