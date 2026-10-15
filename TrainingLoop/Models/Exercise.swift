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

    /// Built-in names follow the interface language.
    var name: String {
        if let builtin {
            return builtin.name(languageCode: Bundle.main.preferredLocalizations.first)
        }
        return customName ?? ""
    }
}
