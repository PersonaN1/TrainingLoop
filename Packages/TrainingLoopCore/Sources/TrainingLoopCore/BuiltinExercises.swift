/// An exercise shipped with the app (SPEC D8, D17). Name, measure and weighting are fixed;
/// the stored `Exercise` row refers to it by `key`.
public struct BuiltinExercise: Hashable, Sendable, Identifiable {
    /// Stable identifier; never changes once shipped, even if a name does.
    public let key: String
    public let nameEN: String
    public let nameRU: String
    public let primaryGroup: MuscleGroup
    public let equipment: Equipment
    public let measure: Measure
    public let weighted: Bool

    public var id: String { key }

    /// The name in the interface language; English for any language without a translation.
    public func name(languageCode: String?) -> String {
        languageCode == "ru" ? nameRU : nameEN
    }
}

/// The built-in catalog, as approved in docs/EXERCISES.md. Missing rows are created at launch,
/// so new built-in exercises arrive with app updates (TECH T2).
public enum BuiltinExercises {
    public static func exercise(key: String) -> BuiltinExercise? {
        byKey[key]
    }

    private static let byKey = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    public static let all: [BuiltinExercise] = [
        BuiltinExercise(key: "barbell_back_squat", nameEN: "Barbell Back Squat", nameRU: "Присед со штангой", primaryGroup: .quads, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "front_squat", nameEN: "Front Squat", nameRU: "Фронтальный присед", primaryGroup: .quads, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_press", nameEN: "Leg Press", nameRU: "Жим ногами", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_lunge", nameEN: "Dumbbell Lunge", nameRU: "Выпады с гантелями", primaryGroup: .quads, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "bulgarian_split_squat", nameEN: "Bulgarian Split Squat", nameRU: "Болгарский сплит-присед", primaryGroup: .quads, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_extension", nameEN: "Leg Extension", nameRU: "Разгибание ног в тренажёре", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "smith_machine_squat", nameEN: "Smith Machine Squat", nameRU: "Присед в Смите", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "hack_squat", nameEN: "Hack Squat", nameRU: "Гакк-присед", primaryGroup: .quads, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "goblet_squat", nameEN: "Goblet Squat", nameRU: "Гоблет-присед", primaryGroup: .quads, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "air_squat", nameEN: "Air Squat", nameRU: "Приседания без веса", primaryGroup: .quads, equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "romanian_deadlift", nameEN: "Romanian Deadlift", nameRU: "Румынская тяга", primaryGroup: .hamstrings, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "leg_curl", nameEN: "Leg Curl", nameRU: "Сгибание ног в тренажёре", primaryGroup: .hamstrings, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_hip_thrust", nameEN: "Barbell Hip Thrust", nameRU: "Ягодичный мост со штангой", primaryGroup: .glutes, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "standing_calf_raise", nameEN: "Standing Calf Raise", nameRU: "Подъём на носки стоя", primaryGroup: .calves, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_calf_raise", nameEN: "Seated Calf Raise", nameRU: "Подъём на носки сидя", primaryGroup: .calves, equipment: .machine, measure: .reps, weighted: true),
        BuiltinExercise(key: "deadlift", nameEN: "Deadlift", nameRU: "Становая тяга", primaryGroup: .back, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "pull_up", nameEN: "Pull-up", nameRU: "Подтягивания", primaryGroup: .back, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_row", nameEN: "Barbell Row", nameRU: "Тяга штанги в наклоне", primaryGroup: .back, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "one_arm_dumbbell_row", nameEN: "One-Arm Dumbbell Row", nameRU: "Тяга гантели одной рукой", primaryGroup: .back, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "lat_pulldown", nameEN: "Lat Pulldown", nameRU: "Тяга верхнего блока", primaryGroup: .back, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_cable_row", nameEN: "Seated Cable Row", nameRU: "Тяга горизонтального блока", primaryGroup: .back, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "back_extension", nameEN: "Back Extension", nameRU: "Гиперэкстензия", primaryGroup: .back, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "chin_up", nameEN: "Chin-up", nameRU: "Подтягивания обратным хватом", primaryGroup: .back, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "t_bar_row", nameEN: "T-Bar Row", nameRU: "Тяга Т-грифа", primaryGroup: .back, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_shrug", nameEN: "Dumbbell Shrug", nameRU: "Шраги с гантелями", primaryGroup: .traps, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_bench_press", nameEN: "Barbell Bench Press", nameRU: "Жим штанги лёжа", primaryGroup: .chest, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_bench_press", nameEN: "Incline Bench Press", nameRU: "Жим штанги на наклонной скамье", primaryGroup: .chest, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_bench_press", nameEN: "Dumbbell Bench Press", nameRU: "Жим гантелей лёжа", primaryGroup: .chest, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_fly", nameEN: "Dumbbell Fly", nameRU: "Разводка гантелей лёжа", primaryGroup: .chest, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "cable_crossover", nameEN: "Cable Crossover", nameRU: "Сведение рук в кроссовере", primaryGroup: .chest, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "push_up", nameEN: "Push-up", nameRU: "Отжимания", primaryGroup: .chest, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "incline_dumbbell_press", nameEN: "Incline Dumbbell Press", nameRU: "Жим гантелей на наклонной скамье", primaryGroup: .chest, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "overhead_press", nameEN: "Overhead Press", nameRU: "Жим штанги стоя", primaryGroup: .shoulders, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "seated_dumbbell_press", nameEN: "Seated Dumbbell Press", nameRU: "Жим гантелей сидя", primaryGroup: .shoulders, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "lateral_raise", nameEN: "Lateral Raise", nameRU: "Махи гантелями в стороны", primaryGroup: .shoulders, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "rear_delt_fly", nameEN: "Rear Delt Fly", nameRU: "Обратные разведения в наклоне", primaryGroup: .shoulders, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "barbell_curl", nameEN: "Barbell Curl", nameRU: "Подъём штанги на бицепс", primaryGroup: .biceps, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "hammer_curl", nameEN: "Hammer Curl", nameRU: "Молотки с гантелями", primaryGroup: .biceps, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dumbbell_curl", nameEN: "Dumbbell Curl", nameRU: "Сгибание рук с гантелями", primaryGroup: .biceps, equipment: .dumbbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "dip", nameEN: "Dip", nameRU: "Отжимания на брусьях", primaryGroup: .triceps, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "skull_crusher", nameEN: "Skull Crusher", nameRU: "Французский жим лёжа", primaryGroup: .triceps, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "triceps_pushdown", nameEN: "Triceps Pushdown", nameRU: "Разгибание рук на блоке", primaryGroup: .triceps, equipment: .cable, measure: .reps, weighted: true),
        BuiltinExercise(key: "close_grip_bench_press", nameEN: "Close-Grip Bench Press", nameRU: "Жим штанги узким хватом", primaryGroup: .triceps, equipment: .barbell, measure: .reps, weighted: true),
        BuiltinExercise(key: "crunch", nameEN: "Crunch", nameRU: "Скручивания", primaryGroup: .abs, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "hanging_leg_raise", nameEN: "Hanging Leg Raise", nameRU: "Подъём ног в висе", primaryGroup: .abs, equipment: .bodyweight, measure: .reps, weighted: true),
        BuiltinExercise(key: "plank", nameEN: "Plank", nameRU: "Планка", primaryGroup: .abs, equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "side_plank", nameEN: "Side Plank", nameRU: "Боковая планка", primaryGroup: .abs, equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "ab_wheel_rollout", nameEN: "Ab Wheel Rollout", nameRU: "Ролик для пресса", primaryGroup: .abs, equipment: .other, measure: .reps, weighted: false),
        BuiltinExercise(key: "dead_hang", nameEN: "Dead Hang", nameRU: "Вис на перекладине", primaryGroup: .forearms, equipment: .bodyweight, measure: .time, weighted: true),
        BuiltinExercise(key: "weighted_neck_flexion", nameEN: "Weighted Neck Flexion", nameRU: "Сгибание шеи с блином лёжа", primaryGroup: .neck, equipment: .other, measure: .reps, weighted: true),
        BuiltinExercise(key: "kettlebell_swing", nameEN: "Kettlebell Swing", nameRU: "Махи гирей", primaryGroup: .fullBody, equipment: .kettlebell, measure: .reps, weighted: true),
        BuiltinExercise(key: "burpee", nameEN: "Burpee", nameRU: "Бёрпи", primaryGroup: .fullBody, equipment: .bodyweight, measure: .reps, weighted: false),
        BuiltinExercise(key: "farmers_walk", nameEN: "Farmer's Walk", nameRU: "Фермерская прогулка", primaryGroup: .fullBody, equipment: .dumbbell, measure: .time, weighted: true),
    ]
}
