/// How a set of an exercise is recorded (CONTEXT: Measure). Can't change after the first record in history.
public enum Measure: String, Codable, CaseIterable, Sendable {
    case reps
    case time
}

/// Descriptive catalog label (SPEC D2); doesn't affect recording.
public enum Equipment: String, Codable, CaseIterable, Sendable {
    case bodyweight
    case barbell
    case dumbbell
    case kettlebell
    case machine
    case cable
    case band
    case other
}

/// The fixed list of 14 groups (SPEC D9). Statistics by group use the primary group only.
public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest
    case back
    case traps
    case neck
    case shoulders
    case biceps
    case triceps
    case forearms
    case abs
    case quads
    case hamstrings
    case glutes
    case calves
    case fullBody
}
