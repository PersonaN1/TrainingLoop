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

/// The fixed list of 9 groups (SPEC D9). Statistics by group use the primary group only.
/// A group is coarse on purpose; what an exercise works inside it is given by its target muscles.
public enum MuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest
    case back
    case shoulders
    case arms
    case legs
    case abs
    case neck
    case fullBody
    case other

    /// A stored raw value, including those of earlier builds: the leg groups are now legs,
    /// traps are back, biceps, triceps and forearms are arms.
    public init?(storedRawValue: String) {
        switch storedRawValue {
        case "quads", "hamstrings", "glutes", "calves": self = .legs
        case "traps": self = .back
        case "biceps", "triceps", "forearms": self = .arms
        default: self.init(rawValue: storedRawValue)
        }
    }

    /// Its target muscles, in display order; empty for a group that isn't divided.
    public var muscles: [Muscle] {
        Muscle.allCases.filter { $0.group == self }
    }
}

/// A target muscle inside a group (SPEC D9): one exercise of a group may stress different ones,
/// depending on the variation.
public enum Muscle: String, Codable, CaseIterable, Sendable {
    case upperChest
    case midChest
    case lowerChest
    case lats
    case midBack
    case traps
    case lowerBack
    case frontDelts
    case sideDelts
    case rearDelts
    case biceps
    case triceps
    case forearms
    case quads
    case hamstrings
    case glutes
    case adductors
    case calves
    case rectusAbs
    case obliques

    public var group: MuscleGroup {
        switch self {
        case .upperChest, .midChest, .lowerChest: .chest
        case .lats, .midBack, .traps, .lowerBack: .back
        case .frontDelts, .sideDelts, .rearDelts: .shoulders
        case .biceps, .triceps, .forearms: .arms
        case .quads, .hamstrings, .glutes, .adductors, .calves: .legs
        case .rectusAbs, .obliques: .abs
        }
    }
}

extension Muscle {
    /// `muscles` without repeats: those of the primary group first, then the rest, each in catalog order.
    public static func ordered(_ muscles: [Muscle], primary: MuscleGroup) -> [Muscle] {
        let chosen = Set(muscles)
        let all = allCases.filter(chosen.contains)
        return all.filter { $0.group == primary } + all.filter { $0.group != primary }
    }
}
