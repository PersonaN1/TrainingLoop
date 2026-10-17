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
    case band
    case other

    /// A stored raw value, including those of earlier builds: cable is now machine.
    public init?(storedRawValue: String) {
        if storedRawValue == "cable" {
            self = .machine
        } else {
            self.init(rawValue: storedRawValue)
        }
    }
}

/// The fixed list of 12 groups (SPEC D9). Statistics by group use the primary group only.
/// Legs are one group: which leg muscles work depends on how the exercise is done.
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
    case legs
    case fullBody
    case other

    /// A stored raw value, including those of earlier builds: quads, hamstrings, glutes and calves are now legs.
    public init?(storedRawValue: String) {
        switch storedRawValue {
        case "quads", "hamstrings", "glutes", "calves": self = .legs
        default: self.init(rawValue: storedRawValue)
        }
    }
}
