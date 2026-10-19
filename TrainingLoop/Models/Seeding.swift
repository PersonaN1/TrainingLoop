import Foundation
import SwiftData
import TrainingLoopCore

/// Creates the built-in exercises missing from the store, by key (TECH T2): runs on every launch,
/// so built-in exercises added in an update appear without a migration. A built-in exercise the update
/// corrected (group, equipment, weighting) takes the catalog's values; its type only while it has no history.
/// A custom exercise named like a new built-in one gets a free "Name (2)" name: names stay unique (SPEC D8).
enum BuiltinSeeder {
    @MainActor
    static func addMissing(_ context: ModelContext) {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtinKey != nil })
        let stored: [Exercise]
        do {
            stored = try context.fetch(descriptor)
        } catch {
            Persistence.report("Fetching built-in exercises failed", error)
            return
        }
        let present = Dictionary(stored.compactMap { exercise in exercise.builtinKey.map { ($0, exercise) } },
                                 uniquingKeysWith: { first, _ in first })
        var customs: [Exercise]?
        for builtin in BuiltinExercises.all {
            guard let exercise = present[builtin.key] else {
                let added = Exercise(builtin: builtin)
                if customs == nil { customs = fetchCustoms(context) }
                renameClashing(customs ?? [], with: added)
                context.insert(added)
                continue
            }
            // Assigned only when different: an unchanged row stays clean and nothing is saved.
            if exercise.primaryGroup != builtin.primaryGroup { exercise.primaryGroup = builtin.primaryGroup }
            if exercise.equipment != builtin.equipment { exercise.equipment = builtin.equipment }
            if exercise.weighted != builtin.weighted { exercise.weighted = builtin.weighted }
            if exercise.measure != builtin.measure, !context.hasHistory(exercise) { exercise.measure = builtin.measure }
        }
        if context.hasChanges { context.saveOrReport() }
    }

    @MainActor
    private static func fetchCustoms(_ context: ModelContext) -> [Exercise] {
        do {
            return try context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtinKey == nil }))
        } catch {
            Persistence.report("Fetching custom exercises failed", error)
            return []
        }
    }

    @MainActor
    private static func renameClashing(_ customs: [Exercise], with added: Exercise) {
        let builtinNames = added.allNames
        for custom in customs where ExerciseName.problem(custom.name, otherNames: builtinNames) == .duplicate {
            let taken = customs.map(\.name) + builtinNames
            custom.customName = ExerciseName.copyName(of: custom.name, otherNames: taken)
        }
    }
}

/// Target muscles and sides (SPEC D9, D23) for exercises stored before they existed, once: a built-in
/// exercise takes the catalog's, a custom one its old muscle-sized groups (quads, biceps…), primary
/// and secondary. Later the user's choice stays, even an empty one.
enum MuscleMigration {
    private static let key = "musclesMigrated.1"

    @MainActor
    static func runOnce(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises where exercise.musclesRaw.isEmpty {
            if let builtin = exercise.builtin {
                exercise.muscles = builtin.muscles
                exercise.bySide = builtin.bySide
            } else {
                exercise.muscles = ([exercise.primaryGroupRaw] + exercise.secondaryGroupsRaw).compactMap(Muscle.init(rawValue:))
            }
        }
        if context.hasChanges { context.saveOrReport() }
        defaults.set(true, forKey: key)
    }
}

/// Both sides (SPEC D23), once: built-in exercises take the catalog's flag, and the sets already in History
/// of every exercise done with both sides count for both, so volume and its records don't jump.
enum BothSidesMigration {
    private static let key = "bothSidesMigrated.1"

    @MainActor
    static func runOnce(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            if let builtin = exercise.builtin, exercise.bySide != builtin.bySide { exercise.bySide = builtin.bySide }
        }
        var changed: Set<UUID> = []
        var workouts: [PersistentIdentifier: Workout] = [:]
        for exercise in exercises where exercise.bySide {
            let id = exercise.id
            let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate {
                $0.exerciseID == id && !$0.bySide
            }))) ?? []
            for set in sets {
                set.bySide = true
                changed.insert(id)
                if let workout = set.entry?.workout { workouts[workout.persistentModelID] = workout }
            }
        }
        workouts.values.forEach { $0.updateTotals() }
        if context.hasChanges { context.saveOrReport() }
        defaults.set(true, forKey: key)
        RecordRecount.start(changed, context: context)
    }
}

/// Creates the example templates once, on first launch (SPEC D18).
enum ExampleSeeder {
    private static let key = "didSeedExamples"

    @MainActor
    static func seedIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        for (index, example) in ExampleTemplates.all(DefaultNames.examples).enumerated() {
            let template = Template(name: example.name, definition: example.definition, sortIndex: index)
            template.exampleKey = example.key
            context.insert(template)
        }
        context.saveOrReport()
        defaults.set(true, forKey: key)
    }
}

/// Example templates created before they had a key get it, once (TECH T13): those still as they were
/// created, under a default name in any language. An edited one stays the user's own.
enum ExampleKeyMigration {
    private static let key = "exampleKeysAdded.1"

    @MainActor
    static func runOnce(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        let templates = (try? context.fetch(FetchDescriptor<Template>(predicate: #Predicate { $0.exampleKey == nil }))) ?? []
        for template in templates {
            template.exampleKey = ExampleTemplates.all(DefaultNames.examples).first { example in
                DefaultNames.isDefault(template.name, of: example.key)
                    && example.definition.hasSameContent(as: template.definition)
            }?.key
        }
        if context.hasChanges { context.saveOrReport() }
        defaults.set(true, forKey: key)
    }
}

/// Example template names follow the interface language: after switching to Russian, "Full Body"
/// reads "Фулбади". A name the user typed is left alone unless it equals a default name.
enum DefaultNames {
    static var examples: ExampleTemplates.Names {
        ExampleTemplates.Names(
            fullBody: String(localized: "Full Body"),
            legsAndPullUps: String(localized: "Legs + Pull-ups"),
            homeNoEquipment: String(localized: "Home, No Equipment")
        )
    }

    /// `ExampleTemplates` key → the English default name.
    private static let names = ["fullBody": "Full Body", "legsAndPullUps": "Legs + Pull-ups",
                                "homeNoEquipment": "Home, No Equipment"]

    /// Whether `name` is the default name of the example with this key, in any bundled language.
    static func isDefault(_ name: String, of exampleKey: String) -> Bool {
        guard let english = names[exampleKey] else { return false }
        let current = Bundle.main.localizedString(forKey: english, value: english, table: nil)
        return translations().contains { $0.key == name && $0.value == current }
    }

    @MainActor
    static func relocalize(_ context: ModelContext) {
        let names = translations()
        guard let templates = try? context.fetch(FetchDescriptor<Template>()) else { return }
        for template in templates {
            if let name = names[template.name], name != template.name { template.name = name }
        }
        if context.hasChanges { context.saveOrReport() }
    }

    /// The default name in every bundled language → the same name in the current language.
    private static func translations() -> [String: String] {
        let bundles = Bundle.main.localizations.compactMap { language in
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        }
        var result: [String: String] = [:]
        for key in names.values {
            let current = Bundle.main.localizedString(forKey: key, value: key, table: nil)
            result[key] = current
            for bundle in bundles {
                result[bundle.localizedString(forKey: key, value: key, table: nil)] = current
            }
        }
        return result
    }
}
