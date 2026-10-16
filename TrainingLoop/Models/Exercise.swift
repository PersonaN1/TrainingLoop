import Foundation
import SwiftData
import TrainingLoopCore

/// A built-in (`builtinKey` set) or custom exercise (TECH T2). Enums are stored as raw strings,
/// so a value added in a later version doesn't break older rows.
/// Every property has a default and there are no unique constraints, so CloudKit sync can be enabled later.
@Model
final class Exercise {
    var id: UUID = UUID()
    /// Key in `BuiltinExercises`; nil for a custom exercise.
    var builtinKey: String?
    /// The user's name; nil for a built-in exercise, whose name comes from the catalog.
    var customName: String?
    var measureRaw: String = Measure.reps.rawValue
    var weighted: Bool = true
    var primaryGroupRaw: String = MuscleGroup.fullBody.rawValue
    var secondaryGroupsRaw: [String] = []
    var equipmentRaw: String = Equipment.other.rawValue
    var note: String = ""
    var isHidden: Bool = false
    var isArchived: Bool = false
    var createdAt: Date = Date.now

    init(builtin: BuiltinExercise) {
        id = builtin.exerciseID
        builtinKey = builtin.key
        measure = builtin.measure
        weighted = builtin.weighted
        primaryGroup = builtin.primaryGroup
        equipment = builtin.equipment
    }

    init(name: String, measure: Measure, weighted: Bool, primaryGroup: MuscleGroup, equipment: Equipment) {
        customName = name
        self.measure = measure
        self.weighted = weighted
        self.primaryGroup = primaryGroup
        self.equipment = equipment
    }

    var measure: Measure {
        get { Measure(rawValue: measureRaw) ?? .reps }
        set { measureRaw = newValue.rawValue }
    }

    var primaryGroup: MuscleGroup {
        get { MuscleGroup(rawValue: primaryGroupRaw) ?? .fullBody }
        set { primaryGroupRaw = newValue.rawValue }
    }

    var secondaryGroups: [MuscleGroup] {
        get { secondaryGroupsRaw.compactMap(MuscleGroup.init(rawValue:)) }
        set { secondaryGroupsRaw = newValue.map(\.rawValue) }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var builtin: BuiltinExercise? { builtinKey.flatMap(BuiltinExercises.exercise(key:)) }

    /// Built-in names follow the app's interface language (the Exercises String Catalog in TrainingLoopCore).
    var name: String {
        if let builtin {
            return builtin.name(languageCode: Bundle.main.preferredLocalizations.first ?? "en")
        }
        return customName ?? ""
    }

    var isCustom: Bool { builtinKey == nil }

    /// Names that search and the uniqueness check compare against: a built-in exercise in every
    /// language, so a custom "Bench Press" doesn't clash only after the interface language changes.
    var allNames: [String] {
        if let builtin { return ["en", "ru"].map { builtin.name(languageCode: $0) } }
        return [customName ?? ""]
    }
}

extension ModelContext {
    /// Whether the exercise appears in any workout, finished or running (SPEC D8): such an exercise
    /// keeps its type and goes to the archive instead of being deleted.
    func hasHistory(_ exercise: Exercise) -> Bool {
        let id = exercise.id
        let descriptor = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == id })
        return ((try? fetchCount(descriptor)) ?? 0) > 0
    }

    /// Exercises with a recorded weight: only these have a "last time's weight" to fill in (SPEC D7).
    func exerciseIDsWithWeightHistory() -> Set<UUID> {
        let descriptor = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.weightKg != nil })
        return Set(((try? fetch(descriptor)) ?? []).map(\.exerciseID))
    }

    /// Whether a template refers to the exercise; deleting it would leave a gap in the template.
    func isInTemplate(_ exercise: Exercise) -> Bool {
        let templates = (try? fetch(FetchDescriptor<Template>())) ?? []
        return templates.contains { $0.definition.exerciseIDs.contains(exercise.id) }
    }

    func customExerciseCount() -> Int {
        (try? fetchCount(FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtinKey == nil }))) ?? 0
    }
}
