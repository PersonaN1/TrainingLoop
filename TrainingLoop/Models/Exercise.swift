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
    /// Secondary groups of earlier builds; read once into `muscles` (`MuscleMigration`).
    var secondaryGroupsRaw: [String] = []
    /// Target muscles (SPEC D9), any group's; a built-in exercise starts with the catalog's.
    var musclesRaw: [String] = []
    /// Left and right are recorded separately (SPEC D23).
    var bySide: Bool = false
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
        muscles = builtin.muscles
        bySide = builtin.bySide
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
        get { MuscleGroup(storedRawValue: primaryGroupRaw) ?? .fullBody }
        set { primaryGroupRaw = newValue.rawValue }
    }

    /// The primary group's muscles first, then the others, each in catalog order.
    var muscles: [Muscle] {
        get { Muscle.ordered(musclesRaw.compactMap(Muscle.init(rawValue:)), primary: primaryGroup) }
        set { musclesRaw = Muscle.ordered(newValue, primary: primaryGroup).map(\.rawValue) }
    }

    /// The way it records its sets, for the running workout.
    var kind: ActiveWorkout.Kind {
        ActiveWorkout.Kind(measure: measure, weighted: weighted, bySide: bySide)
    }

    var equipment: Equipment {
        get { Equipment(storedRawValue: equipmentRaw) ?? .other }
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
    /// Whether the exercise appears in a finished workout (SPEC D8): such an exercise keeps its type and
    /// goes to the archive instead of being deleted. The running workout is asked separately
    /// (`WorkoutController.uses`): it lives in a file, not in the store.
    /// When the store can't tell, the answer is yes: nothing gets deleted by mistake.
    func hasHistory(_ exercise: Exercise) -> Bool {
        let id = exercise.id
        let descriptor = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == id })
        do {
            return try fetchCount(descriptor) > 0
        } catch {
            Persistence.logger.error("Counting an exercise's history failed: \(String(describing: error), privacy: .public)")
            return true
        }
    }

    /// Which of these exercises have a recorded weight: only those have a "last time's weight" to fill in
    /// (SPEC D7). Counted per exercise, so no set is loaded.
    func exerciseIDsWithWeightHistory(among ids: some Sequence<UUID>) -> Set<UUID> {
        Set(ids.filter { id in
            let descriptor = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseID == id && $0.weightKg != nil })
            return ((try? fetchCount(descriptor)) ?? 0) > 0
        })
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
