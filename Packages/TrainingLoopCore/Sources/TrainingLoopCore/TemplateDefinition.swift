import Foundation

/// The whole structure of a template, stored as one JSON value (TECH T2, ADR 0001).
public struct TemplateDefinition: Codable, Hashable, Sendable {
    public var items: [TemplateItem]

    public init(items: [TemplateItem] = []) {
        self.items = items
    }

    /// Every exercise in order, superset members included.
    public var exercises: [TemplateExercise] {
        items.flatMap { item -> [TemplateExercise] in
            switch item {
            case .exercise(let exercise): [exercise]
            case .superset(let superset): superset.exercises
            }
        }
    }

    public var exerciseIDs: [UUID] { exercises.map(\.exerciseID) }
}

/// A top-level element of a template: a single exercise or a superset (no nesting, SPEC D3).
public enum TemplateItem: Hashable, Sendable {
    case exercise(TemplateExercise)
    case superset(TemplateSuperset)
}

extension TemplateItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind, exercise, superset
    }

    private enum Kind: String, Codable {
        case exercise, superset
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .exercise: self = .exercise(try container.decode(TemplateExercise.self, forKey: .exercise))
        case .superset: self = .superset(try container.decode(TemplateSuperset.self, forKey: .superset))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .exercise(let exercise):
            try container.encode(Kind.exercise, forKey: .kind)
            try container.encode(exercise, forKey: .exercise)
        case .superset(let superset):
            try container.encode(Kind.superset, forKey: .kind)
            try container.encode(superset, forKey: .superset)
        }
    }
}

/// An exercise with its planned sets. Inside a superset its own rest is unused: the superset's rests apply.
public struct TemplateExercise: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// `Exercise.id` of the stored exercise, built-in or custom.
    public var exerciseID: UUID
    public var sets: [PlannedSet]
    public var restSeconds: Int

    public init(id: UUID = UUID(), exerciseID: UUID, sets: [PlannedSet], restSeconds: Int) {
        self.id = id
        self.exerciseID = exerciseID
        self.sets = sets
        self.restSeconds = restSeconds
    }
}

/// One planned set (SPEC D4). Reps or seconds depending on the exercise's measure;
/// weight is optional — when missing, the previous time's weight is offered (D7).
public struct PlannedSet: Codable, Hashable, Sendable {
    public var reps: Int?
    public var seconds: Int?
    public var weightKg: Double?

    public init(reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil) {
        self.reps = reps
        self.seconds = seconds
        self.weightKg = weightKg
    }

    /// Only what an exercise records (D2): reps or seconds by its measure, the weight when it is weighted.
    public func fitted(measure: Measure, weighted: Bool) -> PlannedSet {
        PlannedSet(reps: measure == .reps ? reps : nil, seconds: measure == .time ? seconds : nil,
                   weightKg: weighted ? weightKg : nil)
    }
}

/// Two or more neighbouring exercises done in rounds (SPEC D3).
public struct TemplateSuperset: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var exercises: [TemplateExercise]
    /// Rest between exercises inside a round.
    public var restWithinSeconds: Int
    /// Rest after a round.
    public var restAfterSeconds: Int

    public init(id: UUID = UUID(), exercises: [TemplateExercise], restWithinSeconds: Int, restAfterSeconds: Int) {
        self.id = id
        self.exercises = exercises
        self.restWithinSeconds = restWithinSeconds
        self.restAfterSeconds = restAfterSeconds
    }
}
