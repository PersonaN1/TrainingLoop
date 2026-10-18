import Foundation

extension TemplateItem: Identifiable {
    /// The exercise's or the superset's ID.
    public var id: UUID {
        switch self {
        case .exercise(let exercise): exercise.id
        case .superset(let superset): superset.id
        }
    }

    public var isSuperset: Bool {
        if case .superset = self { true } else { false }
    }

    public var exercises: [TemplateExercise] {
        switch self {
        case .exercise(let exercise): [exercise]
        case .superset(let superset): superset.exercises
        }
    }
}

extension TemplateExercise {
    /// A newly added exercise (SPEC D4): one set of 10 reps or 45 s, no weight; more are a tap away.
    public static func new(exerciseID: UUID, measure: Measure, restSeconds: Int) -> TemplateExercise {
        TemplateExercise(exerciseID: exerciseID,
                         sets: [.default(for: measure)],
                         restSeconds: restSeconds)
    }

    /// The same exercise with fresh IDs, for "Duplicate".
    func copy() -> TemplateExercise {
        TemplateExercise(exerciseID: exerciseID, sets: sets, restSeconds: restSeconds)
    }
}

extension PlannedSet {
    public static func `default`(for measure: Measure) -> PlannedSet {
        switch measure {
        case .reps: PlannedSet(reps: 10)
        case .time: PlannedSet(seconds: 45)
        }
    }

    /// Something to record: an empty set can't be ticked from the lock screen (D7).
    public var hasValue: Bool { reps != nil || seconds != nil || weightKg != nil }
}

// MARK: Editing (DESIGN V6)

extension TemplateDefinition {
    public enum MergeError: Error, Equatable, Sendable {
        /// Fewer than two exercises, or the selection isn't a run of neighbouring items.
        case notContiguous
        /// The selection already is one whole superset.
        case alreadySuperset
    }

    /// "Merge into Superset" (SPEC D3): neighbouring top-level items become one superset.
    /// A selected superset brings all its exercises; the first selected superset keeps its rests.
    public mutating func mergeIntoSuperset(itemIDs: Set<UUID>, restWithinSeconds: Int,
                                           restAfterSeconds: Int) throws(MergeError) {
        let positions = items.indices.filter { itemIDs.contains(items[$0].id) }
        guard positions.count == itemIDs.count,
              let first = positions.first, let last = positions.last,
              last - first + 1 == positions.count
        else { throw .notContiguous }
        let selected = items[first...last]
        let members = selected.flatMap(\.exercises)
        guard members.count >= 2 else { throw .notContiguous }
        if selected.count == 1 { throw .alreadySuperset }

        let existing = selected.lazy.compactMap { item -> TemplateSuperset? in
            if case .superset(let superset) = item { superset } else { nil }
        }.first
        let superset = TemplateSuperset(
            id: existing?.id ?? UUID(),
            exercises: members,
            restWithinSeconds: existing?.restWithinSeconds ?? restWithinSeconds,
            restAfterSeconds: existing?.restAfterSeconds ?? restAfterSeconds
        )
        items.replaceSubrange(first...last, with: [.superset(superset)])
    }

    /// "Split": the superset's exercises become separate items, with their own rests.
    public mutating func splitSuperset(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .superset(let superset) = items[index] else { return }
        items.replaceSubrange(index...index, with: superset.exercises.map(TemplateItem.exercise))
    }

    /// Removes an exercise; a superset left with one exercise turns back into a plain one.
    public mutating func removeExercise(_ id: UUID) {
        for index in items.indices {
            switch items[index] {
            case .exercise(let exercise) where exercise.id == id:
                items.remove(at: index)
                return
            case .superset(var superset) where superset.exercises.contains(where: { $0.id == id }):
                superset.exercises.removeAll { $0.id == id }
                items[index] = superset.exercises.count == 1 ? .exercise(superset.exercises[0]) : .superset(superset)
                return
            default:
                continue
            }
        }
    }

    /// Puts a copy right after the exercise, inside its superset if it's in one.
    public mutating func duplicateExercise(_ id: UUID) {
        for index in items.indices {
            switch items[index] {
            case .exercise(let exercise) where exercise.id == id:
                items.insert(.exercise(exercise.copy()), at: index + 1)
                return
            case .superset(var superset):
                guard let position = superset.exercises.firstIndex(where: { $0.id == id }) else { continue }
                superset.exercises.insert(superset.exercises[position].copy(), at: position + 1)
                items[index] = .superset(superset)
                return
            default:
                continue
            }
        }
    }

    /// "Replace" (SPEC D6): another exercise in the same place. The sets stay; when the type differs,
    /// each set gets the new type's default value and keeps its weight.
    public mutating func replaceExercise(_ id: UUID, with exerciseID: UUID, measure: Measure) {
        updateExercise(id) { exercise in
            exercise.exerciseID = exerciseID
            exercise.sets = exercise.sets.map { set in
                let fits = measure == .reps ? set.reps != nil : set.seconds != nil
                if fits { return set }
                var converted = PlannedSet.default(for: measure)
                converted.weightKg = set.weightKg
                return converted
            }
        }
    }

    public mutating func updateExercise(_ id: UUID, _ change: (inout TemplateExercise) -> Void) {
        for index in items.indices {
            switch items[index] {
            case .exercise(var exercise) where exercise.id == id:
                change(&exercise)
                items[index] = .exercise(exercise)
                return
            case .superset(var superset):
                guard let position = superset.exercises.firstIndex(where: { $0.id == id }) else { continue }
                change(&superset.exercises[position])
                items[index] = .superset(superset)
                return
            default:
                continue
            }
        }
    }

    public mutating func updateSuperset(_ id: UUID, _ change: (inout TemplateSuperset) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              case .superset(var superset) = items[index] else { return }
        change(&superset)
        items[index] = .superset(superset)
    }

    /// "Add Exercises" from a superset's menu: they go to the end of it.
    public mutating func appendExercises(_ exercises: [TemplateExercise], toSuperset id: UUID) {
        updateSuperset(id) { $0.exercises.append(contentsOf: exercises) }
    }

    /// "Remove from Superset": the exercise goes right after its superset as a plain one.
    public mutating func takeOutOfSuperset(_ exerciseID: UUID) {
        guard let index = items.firstIndex(where: { $0.isSuperset && $0.exercises.contains { $0.id == exerciseID } }),
              case .superset(var superset) = items[index],
              let exercise = superset.exercises.first(where: { $0.id == exerciseID }) else { return }
        superset.exercises.removeAll { $0.id == exerciseID }
        let rest: TemplateItem = superset.exercises.count == 1 ? .exercise(superset.exercises[0]) : .superset(superset)
        items.replaceSubrange(index...index, with: [rest, .exercise(exercise)])
    }

    /// The superset an exercise is in; nil for a plain exercise.
    public func supersetID(containing exerciseID: UUID) -> UUID? {
        items.first { $0.isSuperset && $0.exercises.contains { $0.id == exerciseID } }?.id
    }

    /// "Merge into Superset" with exercises selected one by one (select mode, DESIGN V6).
    /// An exercise of a superset brings the whole superset.
    public mutating func mergeIntoSuperset(exerciseIDs: Set<UUID>, restWithinSeconds: Int,
                                           restAfterSeconds: Int) throws(MergeError) {
        let itemIDs = Set(items.filter { item in item.exercises.contains { exerciseIDs.contains($0.id) } }.map(\.id))
        try mergeIntoSuperset(itemIDs: itemIDs, restWithinSeconds: restWithinSeconds,
                              restAfterSeconds: restAfterSeconds)
    }

    /// Drag in select mode, where every exercise is its own row (DESIGN V6).
    /// Moved exercises keep their superset while they stay next to it, so a superset can be reordered;
    /// dropped between two exercises of a superset, they join it; anywhere else they become plain.
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

        let supersets = Dictionary(uniqueKeysWithValues: items.compactMap { item -> (UUID, TemplateSuperset)? in
            if case .superset(let superset) = item { (superset.id, superset) } else { nil }
        })
        var rebuilt: [TemplateItem] = []
        var used = Set<UUID>()
        var index = 0
        while index < rows.count {
            guard let id = rows[index].group, let template = supersets[id] else {
                rebuilt.append(.exercise(rows[index].exercise))
                index += 1
                continue
            }
            var run: [TemplateExercise] = []
            while index < rows.count, rows[index].group == id {
                run.append(rows[index].exercise)
                index += 1
            }
            if run.count == 1 {
                rebuilt.append(.exercise(run[0]))
            } else {
                // A superset split in two by a drag keeps its ID only once.
                let superset = TemplateSuperset(id: used.contains(id) ? UUID() : id, exercises: run,
                                                restWithinSeconds: template.restWithinSeconds,
                                                restAfterSeconds: template.restAfterSeconds)
                used.insert(id)
                rebuilt.append(.superset(superset))
            }
        }
        items = rebuilt
    }
}

// MARK: Summary (DESIGN V5)

extension TemplateDefinition {
    public var setCount: Int { exercises.reduce(0) { $0 + $1.sets.count } }

    /// Seconds per set in the duration estimate (DESIGN V5).
    public static let secondsPerSet = 40

    /// Sets × ~40 s plus the template's rests. No rest after the very last set.
    public var estimatedSeconds: Int {
        var total = setCount * Self.secondsPerSet
        for item in items {
            switch item {
            case .exercise(let exercise):
                total += exercise.sets.count * exercise.restSeconds
            case .superset(let superset):
                let rounds = superset.exercises.map(\.sets.count).max() ?? 0
                for round in 0..<rounds {
                    let inRound = superset.exercises.filter { $0.sets.count > round }.count
                    total += (inRound - 1) * superset.restWithinSeconds + superset.restAfterSeconds
                }
            }
        }
        if let lastRest = lastRestSeconds { total -= lastRest }
        return max(total, 0)
    }

    /// Rounded up to whole minutes, at least one; nil for an empty template.
    public var estimatedMinutes: Int? {
        setCount == 0 ? nil : max(1, (estimatedSeconds + 59) / 60)
    }

    private var lastRestSeconds: Int? {
        switch items.last {
        case .exercise(let exercise): exercise.sets.isEmpty ? nil : exercise.restSeconds
        case .superset(let superset): superset.exercises.isEmpty ? nil : superset.restAfterSeconds
        case nil: nil
        }
    }
}

/// "4×8", "3×10–12", "3×45 s" on a template card (DESIGN V5).
public struct SetsSummary: Equatable, Sendable {
    public enum Value: Equatable, Sendable {
        case reps(ClosedRange<Int>)
        case seconds(ClosedRange<Int>)
    }

    public let count: Int
    /// nil when no set has a value.
    public let value: Value?

    public init(_ sets: [PlannedSet]) {
        count = sets.count
        let reps = sets.compactMap(\.reps)
        let seconds = sets.compactMap(\.seconds)
        if let low = reps.min(), let high = reps.max() {
            value = .reps(low...high)
        } else if let low = seconds.min(), let high = seconds.max() {
            value = .seconds(low...high)
        } else {
            value = nil
        }
    }
}

public enum TemplateNaming {
    /// "New Workout", then "New Workout 2", "New Workout 3"… among the other templates' names,
    /// cut so the number fits in the name limit.
    public static func unique(_ base: String, among names: some Sequence<String>) -> String {
        let taken = Set(names.map(ExerciseName.key))
        if !taken.contains(ExerciseName.key(base)) { return base }
        var number = 2
        while true {
            let suffix = " \(number)"
            let candidate = String(base.prefix(Limits.maxNameLength - suffix.count)) + suffix
            if !taken.contains(ExerciseName.key(candidate)) { return candidate }
            number += 1
        }
    }
}

/// Weight entry (SPEC D15): steps of 0.25 in the chosen unit, 0–999.75 kg.
public enum WeightInput {
    public static let maxKilograms = 999.75

    /// Kilograms from what was typed in `unit`; accepts "," and "." as the decimal separator.
    /// Empty text is nil (no weight); text that isn't a number is nil too.
    public static func kilograms(from text: String, unit: WeightUnit) -> Double? {
        let normalized = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty, let value = Double(normalized), value.isFinite, value >= 0 else { return nil }
        let rounded = (value * 4).rounded() / 4
        return min(unit.toKilograms(rounded), maxKilograms)
    }

    /// The stored weight in `unit`, rounded to 0.25 for display and editing.
    public static func displayValue(_ kilograms: Double, unit: WeightUnit) -> Double {
        (unit.fromKilograms(kilograms) * 4).rounded() / 4
    }
}

public enum SetRanges {
    /// SPEC D15.
    public static let reps = 1...999
    public static let seconds = 1...3599
}
