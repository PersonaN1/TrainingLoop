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
/// A set of an exercise done with both arms or legs (D23) is `bothSides`: its values are each side's.
/// When the sides differ the set is split: the left side in its own values, the right one in `right`.
public struct PlannedSet: Codable, Hashable, Sendable {
    public var reps: Int?
    public var seconds: Int?
    public var weightKg: Double?
    public var bothSides: Bool
    public var right: Side?

    public init(reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil, bothSides: Bool = false,
                right: Side? = nil) {
        self.reps = reps
        self.seconds = seconds
        self.weightKg = weightKg
        self.bothSides = bothSides || right != nil
        self.right = right
    }

    private enum CodingKeys: String, CodingKey {
        case reps, seconds, weightKg, bothSides, right
    }

    /// Templates and workouts saved by an earlier build have no `bothSides`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reps = try container.decodeIfPresent(Int.self, forKey: .reps)
        seconds = try container.decodeIfPresent(Int.self, forKey: .seconds)
        weightKg = try container.decodeIfPresent(Double.self, forKey: .weightKg)
        right = try container.decodeIfPresent(Side.self, forKey: .right)
        bothSides = try container.decodeIfPresent(Bool.self, forKey: .bothSides) ?? false || right != nil
    }

    /// Left and right have values of their own.
    public var isSplit: Bool { right != nil }

    /// The values of one side.
    public struct Side: Codable, Hashable, Sendable {
        public var reps: Int?
        public var seconds: Int?
        public var weightKg: Double?

        public init(reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil) {
            self.reps = reps
            self.seconds = seconds
            self.weightKg = weightKg
        }
    }

    /// The set without its sides: the left side of a split set, else one side's values.
    public var left: PlannedSet {
        PlannedSet(reps: reps, seconds: seconds, weightKg: weightKg)
    }

    /// Each side as a set of its own, left first; two alike for a set of both sides not split,
    /// one for a set of an exercise without sides. Records and charts take the better side,
    /// volume and total reps add both (D23).
    public var sides: [PlannedSet] {
        if let right { return [left, PlannedSet(reps: right.reps, seconds: right.seconds, weightKg: right.weightKg)] }
        return bothSides ? [left, left] : [self]
    }

    /// Weight × reps of both sides.
    public var volumeKg: Double {
        sides.reduce(0) { $0 + WorkoutVolume.of(weightKg: $1.weightKg, reps: $1.reps) }
    }

    /// Only what an exercise records (D2): reps or seconds by its measure, the weight when it is weighted,
    /// both sides and a split when it is done with both.
    public func fitted(measure: Measure, weighted: Bool, bothSides: Bool = false) -> PlannedSet {
        let fittedRight = bothSides ? right.map { side in
            Side(reps: measure == .reps ? side.reps : nil, seconds: measure == .time ? side.seconds : nil,
                 weightKg: weighted ? side.weightKg : nil)
        } : nil
        return PlannedSet(reps: measure == .reps ? reps : nil, seconds: measure == .time ? seconds : nil,
                          weightKg: weighted ? weightKg : nil, bothSides: bothSides, right: fittedRight)
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
