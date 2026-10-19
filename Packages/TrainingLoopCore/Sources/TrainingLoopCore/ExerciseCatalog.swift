import Foundation

public enum Limits {
    /// The catalog shows no counter; a hint appears only when adding is refused (SPEC D8).
    public static let maxCustomExercises = 1000
    public static let maxTemplates = 100
    /// Exercise, template and workout names (SPEC D15), as in SetLoop.
    public static let maxNameLength = 60
    /// Notes and descriptions (SPEC D15).
    public static let maxNoteLength = 1000
    /// Finished workouts in the history; a warning shows from `historyWarningFrom` (SPEC D16).
    public static let maxWorkouts = 3000
    public static let historyWarningFrom = 2900
}

extension String {
    /// The name cut to `Limits.maxNameLength` characters.
    public var cappedName: String { capped(Limits.maxNameLength) }

    /// The note cut to `Limits.maxNoteLength` characters.
    public var cappedNote: String { capped(Limits.maxNoteLength) }

    private func capped(_ length: Int) -> String {
        count > length ? String(prefix(length)) : self
    }
}

/// Exercise names are unique (SPEC D8). Two names are the same when they differ only in case,
/// "ё"/"е" and other diacritics, or spacing: "Жим лёжа" and " жим  лежа" clash.
public enum ExerciseName {
    public enum Problem: Equatable, Sendable {
        case empty
        case duplicate
    }

    /// The name as saved: trimmed, with inner runs of spaces collapsed, at most 60 characters.
    public static func cleaned(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").cappedName
    }

    /// The comparison key for uniqueness and search.
    public static func key(_ name: String) -> String {
        cleaned(name).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    /// Why `name` can't be saved, given the names of the other exercises (the edited one excluded).
    public static func problem(_ name: String, otherNames: some Sequence<String>) -> Problem? {
        let key = key(name)
        if key.isEmpty { return .empty }
        if otherNames.contains(where: { Self.key($0) == key }) { return .duplicate }
        return nil
    }

    /// A free name for a copy: "Name (2)", "Name (3)"…, cut so the suffix fits in 60 characters.
    public static func copyName(of name: String, otherNames: some Sequence<String>) -> String {
        let taken = Set(otherNames.map(key))
        let base = cleaned(name)
        var number = 2
        while true {
            let suffix = " (\(number))"
            let candidate = String(base.prefix(Limits.maxNameLength - suffix.count)) + suffix
            if !taken.contains(key(candidate)) { return candidate }
            number += 1
        }
    }
}

/// The catalog filter (DESIGN V10): one muscle group, one kind of equipment, only custom ones,
/// only ones done in some workout.
public struct ExerciseFilter: Equatable, Sendable {
    public var group: MuscleGroup? {
        didSet { if let muscle, muscle.group != group { self.muscle = nil } }
    }
    /// A target muscle of `group`; only with a group chosen.
    public var muscle: Muscle?
    public var equipment: Equipment?
    public var onlyCustom = false
    public var onlyDone = false

    public init(group: MuscleGroup? = nil, muscle: Muscle? = nil, equipment: Equipment? = nil,
                onlyCustom: Bool = false, onlyDone: Bool = false) {
        self.group = group
        self.muscle = muscle?.group == group ? muscle : nil
        self.equipment = equipment
        self.onlyCustom = onlyCustom
        self.onlyDone = onlyDone
    }

    /// Number of active conditions, for "Filter (N)".
    public var activeCount: Int {
        (group == nil ? 0 : 1) + (muscle == nil ? 0 : 1) + (equipment == nil ? 0 : 1) + (onlyCustom ? 1 : 0)
            + (onlyDone ? 1 : 0)
    }

    public var isActive: Bool { activeCount > 0 }

    /// Filters by the primary group, like statistics, then by its target muscles (SPEC D9).
    public func matches(primaryGroup: MuscleGroup, muscles: [Muscle] = [], equipment: Equipment, isCustom: Bool,
                        isDone: Bool = false) -> Bool {
        if let group, group != primaryGroup { return false }
        if let muscle, !muscles.contains(muscle) { return false }
        if let wanted = self.equipment, wanted != equipment { return false }
        if onlyCustom && !isCustom { return false }
        if onlyDone && !isDone { return false }
        return true
    }
}

public enum ExerciseSearch {
    /// Every word of the query occurs in one of the names. Built-in exercises pass their name
    /// in each language, so "squat" finds «Присед» in the Russian interface too.
    public static func matches(_ query: String, names: [String]) -> Bool {
        let words = ExerciseName.key(query).split(separator: " ")
        if words.isEmpty { return true }
        let keys = names.map(ExerciseName.key)
        return keys.contains { key in words.allSatisfy { key.contains($0) } }
    }
}

/// One recorded set, as far as the catalog row needs it.
public struct PerformedSet: Sendable {
    public var reps: Int?
    public var seconds: Int?
    public var weightKg: Double?
    public var workoutStartedAt: Date

    public init(reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil, workoutStartedAt: Date) {
        self.reps = reps
        self.seconds = seconds
        self.weightKg = weightKg
        self.workoutStartedAt = workoutStartedAt
    }
}

/// "N workouts · best result" under the name in the catalog (DESIGN V10).
public struct ExerciseSummary: Equatable, Sendable {
    public enum Best: Equatable, Sendable {
        /// Heaviest real set; ties go to more reps.
        case weight(kg: Double, reps: Int)
        case reps(Int)
        case seconds(Int)
    }

    public let workoutCount: Int
    public let best: Best?

    public init(sets: [PerformedSet], measure: Measure) {
        workoutCount = Set(sets.map(\.workoutStartedAt)).count
        switch measure {
        case .time:
            best = sets.compactMap(\.seconds).max().map(Best.seconds)
        case .reps:
            let weighted = sets.compactMap { set -> (kg: Double, reps: Int)? in
                guard let kg = set.weightKg, kg > 0, let reps = set.reps else { return nil }
                return (kg, reps)
            }
            if let top = weighted.max(by: { ($0.kg, $0.reps) < ($1.kg, $1.reps) }) {
                best = .weight(kg: top.kg, reps: top.reps)
            } else {
                best = sets.compactMap(\.reps).max().map(Best.reps)
            }
        }
    }
}
