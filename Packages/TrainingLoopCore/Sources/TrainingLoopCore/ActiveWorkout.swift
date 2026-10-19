import Foundation

/// The workout in progress (SPEC D6, D7, D19; DESIGN V3, V4). Kept as one JSON file and saved after every
/// action; it becomes a history record only on "Save", so unfinished workouts never reach the statistics.
public struct ActiveWorkout: Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    /// The template it started from; nil for a free workout.
    public var templateID: UUID?
    public var startedAt: Date
    /// Last mark or edit: finds a forgotten workout (D19).
    public var lastActivityAt: Date
    public var items: [Item]
    public var rest: Rest?

    public init(id: UUID = UUID(), name: String, templateID: UUID? = nil, startedAt: Date, items: [Item] = []) {
        self.id = id
        self.name = name
        self.templateID = templateID
        self.startedAt = startedAt
        self.lastActivityAt = startedAt
        self.items = items
    }

    /// A single exercise or a superset, as in a template.
    public enum Item: Codable, Hashable, Sendable, Identifiable {
        case exercise(Exercise)
        case superset(Superset)

        public var id: UUID {
            switch self {
            case .exercise(let exercise): exercise.id
            case .superset(let superset): superset.id
            }
        }

        public var exercises: [Exercise] {
            switch self {
            case .exercise(let exercise): [exercise]
            case .superset(let superset): superset.exercises
            }
        }

        public var isSuperset: Bool {
            if case .superset = self { true } else { false }
        }
    }

    public struct Exercise: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var exerciseID: UUID
        public var restSeconds: Int
        public var sets: [SetRow]

        public init(id: UUID = UUID(), exerciseID: UUID, restSeconds: Int, sets: [SetRow]) {
            self.id = id
            self.exerciseID = exerciseID
            self.restSeconds = restSeconds
            self.sets = sets
        }
    }

    public struct Superset: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        public var exercises: [Exercise]
        public var restWithinSeconds: Int
        public var restAfterSeconds: Int

        public init(id: UUID = UUID(), exercises: [Exercise], restWithinSeconds: Int, restAfterSeconds: Int) {
            self.id = id
            self.exercises = exercises
            self.restWithinSeconds = restWithinSeconds
            self.restAfterSeconds = restAfterSeconds
        }
    }

    /// One set row (D7).
    public struct SetRow: Codable, Hashable, Sendable, Identifiable {
        public var id: UUID
        /// From the template; what "Update template" keeps (D6: changed values don't count).
        public var planned: PlannedSet
        /// The same-numbered set of the last workout with this exercise: the "Last time" column.
        public var previous: PlannedSet?
        /// Typed by the user; a nil field shows the suggestion in grey.
        public var entered: PlannedSet
        public var doneAt: Date?
        /// The exercise is done with both arms or legs (D23): one line counts for each side.
        public var bySide: Bool
        /// The sides differ: a line for each, L and R; the values are the left side, `right` the right one.
        /// One tick covers both.
        public var isSplit: Bool

        public init(id: UUID = UUID(), planned: PlannedSet, previous: PlannedSet?,
                    entered: PlannedSet = PlannedSet(), doneAt: Date? = nil, bySide: Bool = false,
                    isSplit: Bool = false) {
            self.id = id
            self.planned = planned
            self.previous = previous
            self.entered = entered
            self.doneAt = doneAt
            self.bySide = bySide || isSplit
            self.isSplit = isSplit
        }

        private enum CodingKeys: String, CodingKey {
            case id, planned, previous, entered, doneAt, bySide, isSplit
        }

        /// A workout saved by an earlier build has no `bySide` nor `isSplit`.
        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            planned = try container.decode(PlannedSet.self, forKey: .planned)
            previous = try container.decodeIfPresent(PlannedSet.self, forKey: .previous)
            entered = try container.decode(PlannedSet.self, forKey: .entered)
            doneAt = try container.decodeIfPresent(Date.self, forKey: .doneAt)
            bySide = try container.decodeIfPresent(Bool.self, forKey: .bySide) ?? false
            isSplit = try container.decodeIfPresent(Bool.self, forKey: .isSplit) ?? false
        }

        public var isDone: Bool { doneAt != nil }

        /// Template value, else last time's, else empty (D7). The template's value is for both sides;
        /// last time's right side suggests the right side, or its only value when it wasn't split.
        public var suggested: PlannedSet {
            var result = PlannedSet(reps: planned.reps ?? previous?.reps,
                                    seconds: planned.seconds ?? previous?.seconds,
                                    weightKg: planned.weightKg ?? previous?.weightKg, bothSides: bySide)
            if isSplit {
                let plannedRight = planned.right ?? PlannedSet.Side(reps: planned.reps, seconds: planned.seconds,
                                                                     weightKg: planned.weightKg)
                let previousRight = previous?.right
                    ?? previous.map { PlannedSet.Side(reps: $0.reps, seconds: $0.seconds, weightKg: $0.weightKg) }
                result.right = PlannedSet.Side(reps: plannedRight.reps ?? previousRight?.reps,
                                               seconds: plannedRight.seconds ?? previousRight?.seconds,
                                               weightKg: plannedRight.weightKg ?? previousRight?.weightKg)
            }
            return result
        }

        /// What a tick records: the typed values over the suggestion.
        public var value: PlannedSet {
            let suggested = suggested
            var result = PlannedSet(reps: entered.reps ?? suggested.reps,
                                    seconds: entered.seconds ?? suggested.seconds,
                                    weightKg: entered.weightKg ?? suggested.weightKg, bothSides: bySide)
            if let right = suggested.right {
                result.right = PlannedSet.Side(reps: entered.right?.reps ?? right.reps,
                                               seconds: entered.right?.seconds ?? right.seconds,
                                               weightKg: entered.right?.weightKg ?? right.weightKg)
            }
            return result
        }

        /// Ticking needs what the exercise records: reps, or time (D7), on both sides of a set by sides.
        /// Unticking always works.
        public func canTick(measure: Measure) -> Bool {
            isDone || value.sides.allSatisfy { measure == .reps ? $0.reps != nil : $0.seconds != nil }
        }
    }

    /// The rest countdown: an end time, not a counter, so a frozen app still shows the right time (TECH T6).
    public struct Rest: Codable, Hashable, Sendable {
        public var endsAt: Date
        public var totalSeconds: Int
        /// Time left when paused (SPEC D19: only the rest has a pause); `endsAt` is moved on resume.
        public var pausedLeft: TimeInterval?

        public init(endsAt: Date, totalSeconds: Int, pausedLeft: TimeInterval? = nil) {
            self.endsAt = endsAt
            self.totalSeconds = totalSeconds
            self.pausedLeft = pausedLeft
        }

        public var isPaused: Bool { pausedLeft != nil }

        public func left(at date: Date) -> TimeInterval {
            pausedLeft ?? max(0, endsAt.timeIntervalSince(date))
        }
    }
}

// MARK: - Starting

extension ActiveWorkout {
    /// A copy of the template (D6). `previous` gives last time's sets of each exercise, in order.
    public init(template definition: TemplateDefinition, name: String, templateID: UUID?, startedAt: Date,
                previous: [UUID: [PlannedSet]]) {
        func exercise(_ planned: TemplateExercise) -> Exercise {
            let last = previous[planned.exerciseID] ?? []
            return Exercise(exerciseID: planned.exerciseID, restSeconds: planned.restSeconds,
                            sets: planned.sets.enumerated().map { index, set in
                                SetRow(planned: set, previous: index < last.count ? last[index] : nil)
                            })
        }
        let items: [Item] = definition.items.map { item in
            switch item {
            case .exercise(let planned): .exercise(exercise(planned))
            case .superset(let superset):
                .superset(Superset(exercises: superset.exercises.map(exercise),
                                   restWithinSeconds: superset.restWithinSeconds,
                                   restAfterSeconds: superset.restAfterSeconds))
            }
        }
        self.init(name: name, templateID: templateID, startedAt: startedAt, items: items)
    }

    /// An exercise added during the workout: last time's sets, or `defaultSets` empty ones (one; more are a tap away).
    public static func newExercise(_ exerciseID: UUID, restSeconds: Int, previous: [PlannedSet],
                                   defaultSets: Int = 1) -> Exercise {
        let sets = previous.isEmpty
            ? (0..<defaultSets).map { _ in SetRow(planned: PlannedSet(), previous: nil) }
            : previous.map { SetRow(planned: PlannedSet(), previous: $0) }
        return Exercise(exerciseID: exerciseID, restSeconds: restSeconds, sets: sets)
    }
}

// MARK: - Order of sets

extension ActiveWorkout {
    /// Where a set is: item, exercise in the item, set in the exercise.
    public struct Position: Hashable, Sendable {
        public var item: Int
        public var exercise: Int
        public var set: Int

        public init(item: Int, exercise: Int, set: Int) {
            self.item = item
            self.exercise = exercise
            self.set = set
        }
    }

    /// Every set in the order it is done: an exercise's sets one after another; a superset in rounds,
    /// one set of each exercise that still has one (D3).
    public var order: [Position] {
        var result: [Position] = []
        for (itemIndex, item) in items.enumerated() {
            let exercises = item.exercises
            let rounds = exercises.map(\.sets.count).max() ?? 0
            if item.isSuperset {
                for round in 0..<rounds {
                    for (exerciseIndex, exercise) in exercises.enumerated() where round < exercise.sets.count {
                        result.append(Position(item: itemIndex, exercise: exerciseIndex, set: round))
                    }
                }
            } else {
                for set in 0..<rounds {
                    result.append(Position(item: itemIndex, exercise: 0, set: set))
                }
            }
        }
        return result
    }

    public subscript(position: Position) -> SetRow {
        items[position.item].exercises[position.exercise].sets[position.set]
    }

    public func exercise(at position: Position) -> Exercise {
        items[position.item].exercises[position.exercise]
    }

    public func position(of setID: UUID) -> Position? {
        order.first { self[$0].id == setID }
    }

    /// The highlighted set: the first one in `order` not done yet.
    public var nextPosition: Position? {
        order.first { !self[$0].isDone }
    }

    /// The rest after finishing the set at `position` (D5): an exercise's own rest; in a superset, the rest
    /// inside the round while the round goes on, the rest after it at its end.
    public func restSeconds(after position: Position) -> Int {
        switch items[position.item] {
        case .exercise(let exercise):
            return exercise.restSeconds
        case .superset(let superset):
            let laterInRound = superset.exercises.indices.contains {
                $0 > position.exercise && position.set < superset.exercises[$0].sets.count
            }
            return laterInRound ? superset.restWithinSeconds : superset.restAfterSeconds
        }
    }

    public var setCount: Int { items.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } } }
    public var doneSetCount: Int { items.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.filter(\.isDone).count } } }
}

// MARK: - Editing

extension ActiveWorkout {
    /// Changes the exercise with `id` wherever it is.
    public mutating func updateExercise(_ id: UUID, _ change: (inout Exercise) -> Void) {
        for index in items.indices {
            switch items[index] {
            case .exercise(var exercise) where exercise.id == id:
                change(&exercise)
                items[index] = .exercise(exercise)
                return
            case .superset(var superset):
                if let inner = superset.exercises.firstIndex(where: { $0.id == id }) {
                    change(&superset.exercises[inner])
                    items[index] = .superset(superset)
                    return
                }
            default:
                continue
            }
        }
    }

    public mutating func updateSet(_ id: UUID, _ change: (inout SetRow) -> Void) {
        guard let position = position(of: id) else { return }
        updateExercise(exercise(at: position).id) { change(&$0.sets[position.set]) }
    }

    /// "+ Set" copies the last row as shown, suggestions included (D4): the new set has no "Last time"
    /// of its own to suggest from.
    public mutating func addSet(to exerciseID: UUID) {
        updateExercise(exerciseID) { exercise in
            guard let last = exercise.sets.last else {
                exercise.sets.append(SetRow(planned: PlannedSet(), previous: nil))
                return
            }
            exercise.sets.append(SetRow(planned: last.planned, previous: nil, entered: last.value, bySide: last.bySide,
                                        isSplit: last.isSplit))
        }
    }

    /// "Split into L and R" (D23): the set gets a line for each side, both starting from what it shows.
    /// Joining keeps the left side's values for both.
    public mutating func setSplit(_ id: UUID, _ isSplit: Bool) {
        updateSet(id) { set in
            guard set.bySide, set.isSplit != isSplit else { return }
            if isSplit {
                let value = set.value
                set.entered = PlannedSet(reps: value.reps, seconds: value.seconds, weightKg: value.weightKg,
                                         right: .init(reps: value.reps, seconds: value.seconds, weightKg: value.weightKg))
            } else {
                set.entered.right = nil
            }
            set.isSplit = isSplit
        }
    }

    public mutating func removeSet(_ id: UUID) {
        guard let position = position(of: id) else { return }
        let exercise = exercise(at: position)
        if exercise.sets.count == 1 {
            removeExercise(exercise.id)
        } else {
            updateExercise(exercise.id) { $0.sets.remove(at: position.set) }
        }
    }

    /// Takes an exercise out; a superset left with one exercise becomes a plain one.
    public mutating func removeExercise(_ id: UUID) {
        for index in items.indices.reversed() {
            switch items[index] {
            case .exercise(let exercise) where exercise.id == id:
                items.remove(at: index)
                return
            case .superset(var superset):
                guard let inner = superset.exercises.firstIndex(where: { $0.id == id }) else { continue }
                superset.exercises.remove(at: inner)
                if superset.exercises.count == 1 {
                    var only = superset.exercises[0]
                    only.restSeconds = superset.restAfterSeconds
                    items[index] = .exercise(only)
                } else {
                    items[index] = .superset(superset)
                }
                return
            default:
                continue
            }
        }
    }

    /// "Change Order" (D6), as in the template editor: moved exercises keep their superset while they stay
    /// next to it; dropped between two exercises of a superset they join it; anywhere else they become plain.
    public mutating func moveExercises(fromOffsets source: IndexSet, toOffset destination: Int) {
        var rows = items.flatMap { item in
            item.exercises.map { (exercise: $0, group: item.isSuperset ? item.id : nil) }
        }
        let ownGroups = Set(source.map { rows[$0].group })
        let start = destination - source.filter { $0 < destination }.count
        let moved = source.map { rows[$0] }
        for index in source.reversed() { rows.remove(at: index) }
        rows.insert(contentsOf: moved, at: start)
        let end = start + source.count
        let before = start > 0 ? rows[start - 1].group : nil
        let after = end < rows.count ? rows[end].group : nil
        let group: UUID?
        if ownGroups.count == 1, let own = ownGroups.first ?? nil, before == own || after == own {
            group = own
        } else if let before, before == after {
            group = before
        } else {
            group = nil
        }
        for index in start..<end { rows[index].group = group }

        let supersets = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (UUID, Superset)? in
            if case .superset(let superset) = item { (superset.id, superset) } else { nil }
        })
        var rebuilt: [Item] = []
        var used = Set<UUID>()
        var index = 0
        while index < rows.count {
            guard let id = rows[index].group, let old = supersets[id] else {
                rebuilt.append(.exercise(rows[index].exercise))
                index += 1
                continue
            }
            var run: [Exercise] = []
            while index < rows.count, rows[index].group == id {
                run.append(rows[index].exercise)
                index += 1
            }
            if run.count == 1 {
                var only = run[0]
                only.restSeconds = old.restAfterSeconds
                rebuilt.append(.exercise(only))
            } else {
                // A superset split in two by a drag keeps its ID only once.
                rebuilt.append(.superset(Superset(id: used.contains(id) ? UUID() : id, exercises: run,
                                                  restWithinSeconds: old.restWithinSeconds,
                                                  restAfterSeconds: old.restAfterSeconds)))
                used.insert(id)
            }
        }
        items = rebuilt
    }

    /// "Replace": another exercise from the catalog with fresh sets. Done sets stay with the old exercise
    /// (D7: ticked sets are saved); the new one then follows it with the sets still to do.
    /// Planned reps or time carry over; `fitSets` drops them when the measures differ.
    public mutating func replaceExercise(_ id: UUID, with exerciseID: UUID, previous: [PlannedSet]) {
        guard let old = items.flatMap(\.exercises).first(where: { $0.id == id }) else { return }
        let open = old.sets.filter { !$0.isDone }
        let done = old.sets.count - open.count
        let sets = (done == 0 || open.isEmpty ? old.sets : open).enumerated().map { index, set in
            SetRow(planned: PlannedSet(reps: set.planned.reps, seconds: set.planned.seconds),
                   previous: index < previous.count ? previous[index] : nil)
        }
        guard done > 0 else {
            updateExercise(id) { exercise in
                exercise.exerciseID = exerciseID
                exercise.sets = sets
            }
            return
        }
        updateExercise(id) { $0.sets.removeAll { !$0.isDone } }
        insert(Exercise(exerciseID: exerciseID, restSeconds: old.restSeconds, sets: sets), after: id)
    }

    /// Puts `exercise` right after the one with `id`, in its superset if it has one.
    private mutating func insert(_ exercise: Exercise, after id: UUID) {
        for index in items.indices {
            switch items[index] {
            case .exercise(let other) where other.id == id:
                items.insert(.exercise(exercise), at: index + 1)
                return
            case .superset(var superset):
                guard let inner = superset.exercises.firstIndex(where: { $0.id == id }) else { continue }
                superset.exercises.insert(exercise, at: inner + 1)
                items[index] = .superset(superset)
                return
            default:
                continue
            }
        }
    }

    /// The way an exercise records its sets, for `fitSets`.
    public struct Kind: Sendable {
        public var measure: Measure
        public var weighted: Bool
        public var bySide: Bool

        public init(measure: Measure, weighted: Bool, bySide: Bool) {
            self.measure = measure
            self.weighted = weighted
            self.bySide = bySide
        }
    }

    /// Drops the values an exercise doesn't record (D2) from its sets: reps or time of the other measure
    /// (after "Replace"), a weight when "With Weight" is off (from the template or last time), a right
    /// side when it doesn't go by sides; sets of an exercise that does are split (D23).
    /// `kind` gives an exercise's way of recording; an unknown exercise is left as it is.
    public mutating func fitSets(_ kind: (UUID) -> Kind?) {
        for index in items.indices {
            var item = items[index]
            switch item {
            case .exercise(var exercise):
                Self.fit(&exercise, kind)
                item = .exercise(exercise)
            case .superset(var superset):
                for inner in superset.exercises.indices { Self.fit(&superset.exercises[inner], kind) }
                item = .superset(superset)
            }
            items[index] = item
        }
    }

    private static func fit(_ exercise: inout Exercise, _ kind: (UUID) -> Kind?) {
        guard let kind = kind(exercise.exerciseID) else { return }
        for index in exercise.sets.indices {
            var set = exercise.sets[index]
            // A done set keeps its shape: it was recorded the way the exercise went then.
            if !set.isDone {
                set.bySide = kind.bySide
                set.isSplit = set.isSplit && kind.bySide
            }
            set.planned = set.planned.fitted(measure: kind.measure, weighted: kind.weighted, bothSides: set.isSplit)
            set.previous = set.previous.map {
                $0.fitted(measure: kind.measure, weighted: kind.weighted, bothSides: $0.bothSides)
            }
            set.entered = set.entered.fitted(measure: kind.measure, weighted: kind.weighted, bothSides: set.isSplit)
            exercise.sets[index] = set
        }
    }
}

// MARK: - Finishing

extension ActiveWorkout {
    /// Only ticked sets are kept (D7); exercises without them are dropped.
    public var doneItems: [Item] {
        items.compactMap { item in
            switch item {
            case .exercise(var exercise):
                exercise.sets = exercise.sets.filter(\.isDone)
                return exercise.sets.isEmpty ? nil : .exercise(exercise)
            case .superset(var superset):
                superset.exercises = superset.exercises.compactMap { exercise in
                    var exercise = exercise
                    exercise.sets = exercise.sets.filter(\.isDone)
                    return exercise.sets.isEmpty ? nil : exercise
                }
                switch superset.exercises.count {
                case 0: return nil
                case 1: return .exercise(superset.exercises[0])
                default: return .superset(superset)
                }
            }
        }
    }

    /// The last tick, or the start: a finished workout's length runs to its last mark (D19).
    public var lastMarkAt: Date {
        items.flatMap(\.exercises).flatMap(\.sets).compactMap(\.doneAt).max() ?? startedAt
    }

    /// The current list as a template: planned values where the template had them, else what was done.
    public var asTemplate: TemplateDefinition {
        func exercise(_ exercise: Exercise) -> TemplateExercise {
            TemplateExercise(exerciseID: exercise.exerciseID,
                             sets: exercise.sets.map { set in
                                 // A template's value is for both sides (D23).
                                 set.planned.reps == nil && set.planned.seconds == nil ? set.value.left : set.planned.left
                             },
                             restSeconds: exercise.restSeconds)
        }
        return TemplateDefinition(items: items.map { item in
            switch item {
            case .exercise(let planned): .exercise(exercise(planned))
            case .superset(let superset):
                .superset(TemplateSuperset(exercises: superset.exercises.map(exercise),
                                           restWithinSeconds: superset.restWithinSeconds,
                                           restAfterSeconds: superset.restAfterSeconds))
            }
        })
    }

    /// The exercises and set counts differ from the template's (D6); weights and reps don't count.
    public func compositionDiffers(from template: TemplateDefinition) -> Bool {
        func shape(_ items: [[(UUID, Int)]]) -> [[String]] {
            items.map { $0.map { "\($0.0)×\($0.1)" } }
        }
        let mine = items.map { $0.exercises.map { ($0.exerciseID, $0.sets.count) } }
        let theirs = template.items.map { item -> [(UUID, Int)] in
            switch item {
            case .exercise(let exercise): [(exercise.exerciseID, exercise.sets.count)]
            case .superset(let superset): superset.exercises.map { ($0.exerciseID, $0.sets.count) }
            }
        }
        return shape(mine) != shape(theirs)
    }
}
