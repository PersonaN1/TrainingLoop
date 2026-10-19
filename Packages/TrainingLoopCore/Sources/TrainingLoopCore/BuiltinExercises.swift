import Foundation

/// An exercise shipped with the app (SPEC D8, D17). Name, group, measure and weighting are fixed;
/// the stored `Exercise` row refers to it by `key`. Names live in the `Exercises` String Catalog
/// under the same key, translated like any other interface text (TECH T10).
public struct BuiltinExercise: Hashable, Sendable, Identifiable {
    /// Stable identifier; never changes once shipped, even if a name does.
    public let key: String
    public let primaryGroup: MuscleGroup
    /// Target muscles a new row starts with; the user may change them (SPEC D9).
    public let muscles: [Muscle]
    public let equipment: Equipment
    public let measure: Measure
    public let weighted: Bool
    /// Left and right are recorded separately (SPEC D23); the user may change it.
    public let bySide: Bool

    public init(key: String, primaryGroup: MuscleGroup, muscles: [Muscle], equipment: Equipment, measure: Measure,
                weighted: Bool, bySide: Bool = false) {
        self.key = key
        self.primaryGroup = primaryGroup
        self.muscles = muscles
        self.equipment = equipment
        self.measure = measure
        self.weighted = weighted
        self.bySide = bySide
    }

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
        BuiltinExercise(key: "barbell_back_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "front_squat", primaryGroup: .legs, muscles: [.quads], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_press", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_lunge", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "bulgarian_split_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "leg_extension", primaryGroup: .legs, muscles: [.quads], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "hack_squat", primaryGroup: .legs, muscles: [.quads], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "goblet_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "air_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "romanian_deadlift", primaryGroup: .legs, muscles: [.hamstrings, .glutes], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_curl", primaryGroup: .legs, muscles: [.hamstrings], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_hip_thrust", primaryGroup: .legs, muscles: [.glutes], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "standing_calf_raise", primaryGroup: .legs, muscles: [.calves], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_calf_raise", primaryGroup: .legs, muscles: [.calves], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "pendulum_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "belt_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_lunge", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_lunge", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "walking_lunge", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "reverse_lunge", primaryGroup: .legs, muscles: [.glutes, .quads], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "step_up", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "dumbbell_sumo_squat", primaryGroup: .legs, muscles: [.adductors, .glutes, .quads], equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "sissy_squat", primaryGroup: .legs, muscles: [.quads], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "pistol_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .bodyweight, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "jump_squat", primaryGroup: .legs, muscles: [.quads, .glutes], equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "wall_sit", primaryGroup: .legs, muscles: [.quads], equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "dumbbell_romanian_deadlift", primaryGroup: .legs, muscles: [.hamstrings, .glutes], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "good_morning", primaryGroup: .legs, muscles: [.hamstrings, .lowerBack], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_leg_curl", primaryGroup: .legs, muscles: [.hamstrings], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "nordic_curl", primaryGroup: .legs, muscles: [.hamstrings], equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "glute_bridge", primaryGroup: .legs, muscles: [.glutes], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "cable_glute_kickback", primaryGroup: .legs, muscles: [.glutes], equipment: .machine, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "hip_abduction", primaryGroup: .legs, muscles: [.glutes], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "hip_adduction", primaryGroup: .legs, muscles: [.adductors], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_press_calf_raise", primaryGroup: .legs, muscles: [.calves], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "deadlift", primaryGroup: .back, muscles: [.lowerBack, .glutes, .hamstrings], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "pull_up", primaryGroup: .back, muscles: [.lats, .biceps], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_row", primaryGroup: .back, muscles: [.midBack, .lats], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "one_arm_dumbbell_row", primaryGroup: .back, muscles: [.lats, .midBack], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "lat_pulldown", primaryGroup: .back, muscles: [.lats], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_cable_row", primaryGroup: .back, muscles: [.midBack, .lats], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "back_extension", primaryGroup: .back, muscles: [.lowerBack, .glutes], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "chin_up", primaryGroup: .back, muscles: [.lats, .biceps], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "t_bar_row", primaryGroup: .back, muscles: [.midBack, .lats], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "sumo_deadlift", primaryGroup: .back, muscles: [.lowerBack, .glutes, .adductors], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "trap_bar_deadlift", primaryGroup: .back, muscles: [.lowerBack, .quads, .glutes], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "rack_pull", primaryGroup: .back, muscles: [.lowerBack, .traps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "wide_grip_pull_up", primaryGroup: .back, muscles: [.lats], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "inverted_row", primaryGroup: .back, muscles: [.midBack, .lats], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "close_grip_lat_pulldown", primaryGroup: .back, muscles: [.lats, .midBack], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "straight_arm_pulldown", primaryGroup: .back, muscles: [.lats], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "machine_row", primaryGroup: .back, muscles: [.midBack, .lats], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "chest_supported_dumbbell_row", primaryGroup: .back, muscles: [.midBack, .rearDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "dumbbell_shrug", primaryGroup: .back, muscles: [.traps], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "barbell_shrug", primaryGroup: .back, muscles: [.traps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_bench_press", primaryGroup: .chest, muscles: [.midChest, .triceps, .frontDelts], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_bench_press", primaryGroup: .chest, muscles: [.upperChest, .frontDelts], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_bench_press", primaryGroup: .chest, muscles: [.midChest], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "dumbbell_fly", primaryGroup: .chest, muscles: [.midChest], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "cable_crossover", primaryGroup: .chest, muscles: [.lowerChest, .midChest], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "push_up", primaryGroup: .chest, muscles: [.midChest, .triceps], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_dumbbell_press", primaryGroup: .chest, muscles: [.upperChest, .frontDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "decline_bench_press", primaryGroup: .chest, muscles: [.lowerChest, .triceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_bench_press", primaryGroup: .chest, muscles: [.midChest, .triceps], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_incline_press", primaryGroup: .chest, muscles: [.upperChest, .frontDelts], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "machine_chest_press", primaryGroup: .chest, muscles: [.midChest], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "pec_deck", primaryGroup: .chest, muscles: [.midChest], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_dumbbell_fly", primaryGroup: .chest, muscles: [.upperChest], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "dumbbell_pullover", primaryGroup: .chest, muscles: [.midChest, .lats], equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "overhead_press", primaryGroup: .shoulders, muscles: [.frontDelts, .triceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_dumbbell_press", primaryGroup: .shoulders, muscles: [.frontDelts, .sideDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "lateral_raise", primaryGroup: .shoulders, muscles: [.sideDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "rear_delt_fly", primaryGroup: .shoulders, muscles: [.rearDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "behind_the_neck_press", primaryGroup: .shoulders, muscles: [.frontDelts, .sideDelts], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "push_press", primaryGroup: .shoulders, muscles: [.frontDelts, .triceps, .quads], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "arnold_press", primaryGroup: .shoulders, muscles: [.frontDelts, .sideDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "machine_shoulder_press", primaryGroup: .shoulders, muscles: [.frontDelts], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_shoulder_press", primaryGroup: .shoulders, muscles: [.frontDelts], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "cable_lateral_raise", primaryGroup: .shoulders, muscles: [.sideDelts], equipment: .machine, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "front_raise", primaryGroup: .shoulders, muscles: [.frontDelts], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "upright_row", primaryGroup: .shoulders, muscles: [.sideDelts, .traps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "reverse_pec_deck", primaryGroup: .shoulders, muscles: [.rearDelts], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "face_pull", primaryGroup: .shoulders, muscles: [.rearDelts, .midBack], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "band_pull_apart", primaryGroup: .shoulders, muscles: [.rearDelts, .midBack], equipment: .band, measure: .reps, weighted: false),
        BuiltinExercise(key: "barbell_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "hammer_curl", primaryGroup: .arms, muscles: [.biceps, .forearms], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "dumbbell_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "ez_bar_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "preacher_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_dumbbell_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "concentration_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "cable_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "machine_preacher_curl", primaryGroup: .arms, muscles: [.biceps], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "dip", primaryGroup: .arms, muscles: [.triceps, .lowerChest], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "skull_crusher", primaryGroup: .arms, muscles: [.triceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "triceps_pushdown", primaryGroup: .arms, muscles: [.triceps], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "close_grip_bench_press", primaryGroup: .arms, muscles: [.triceps, .midChest], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_skull_crusher", primaryGroup: .arms, muscles: [.triceps], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "seated_french_press", primaryGroup: .arms, muscles: [.triceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_overhead_extension", primaryGroup: .arms, muscles: [.triceps], equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "cable_overhead_extension", primaryGroup: .arms, muscles: [.triceps], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "rope_pushdown", primaryGroup: .arms, muscles: [.triceps], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "triceps_kickback", primaryGroup: .arms, muscles: [.triceps], equipment: .dumbbell, measure: .reps, weighted: true, bySide: true),
        BuiltinExercise(key: "bench_dip", primaryGroup: .arms, muscles: [.triceps], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "diamond_push_up", primaryGroup: .arms, muscles: [.triceps, .midChest], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "crunch", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "hanging_leg_raise", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "plank", primaryGroup: .abs, muscles: [.rectusAbs, .obliques], equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "side_plank", primaryGroup: .abs, muscles: [.obliques], equipment: .bodyweight, measure: .time, weighted: true, bySide: true),
        BuiltinExercise(key: "ab_wheel_rollout", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .other, measure: .reps, weighted: false),
        BuiltinExercise(key: "cable_crunch", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "decline_crunch", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "lying_leg_raise", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "hanging_knee_raise", primaryGroup: .abs, muscles: [.rectusAbs], equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "russian_twist", primaryGroup: .abs, muscles: [.obliques], equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "dead_hang", primaryGroup: .arms, muscles: [.forearms], equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "wrist_curl", primaryGroup: .arms, muscles: [.forearms], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "reverse_curl", primaryGroup: .arms, muscles: [.forearms, .biceps], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "weighted_neck_flexion", primaryGroup: .neck, muscles: [], equipment: .other, measure: .reps, weighted: true),
        BuiltinExercise(key: "kettlebell_swing", primaryGroup: .fullBody, muscles: [.glutes, .hamstrings], equipment: .kettlebell, measure: .reps, weighted: true),
        BuiltinExercise(key: "burpee", primaryGroup: .fullBody, muscles: [], equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "farmers_walk", primaryGroup: .fullBody, muscles: [.forearms, .traps], equipment: .dumbbell, measure: .time, weighted: true, bySide: true),
        BuiltinExercise(key: "power_clean", primaryGroup: .fullBody, muscles: [.glutes, .traps, .quads], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "thruster", primaryGroup: .fullBody, muscles: [.quads, .frontDelts], equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "jump_rope", primaryGroup: .fullBody, muscles: [.calves], equipment: .other, measure: .time, weighted: false),
    ]
}
