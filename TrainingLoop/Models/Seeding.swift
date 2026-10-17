import Foundation
import SwiftData
import TrainingLoopCore

/// Creates the built-in exercises missing from the store, by key (TECH T2): runs on every launch,
/// so built-in exercises added in an update appear without a migration. A built-in exercise the update
/// corrected (group, equipment, weighting) takes the catalog's values; its type only while it has no history.
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
        for builtin in BuiltinExercises.all {
            guard let exercise = present[builtin.key] else {
                context.insert(Exercise(builtin: builtin))
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
}

/// Creates the example templates once, on first launch (SPEC D18).
enum ExampleSeeder {
    private static let key = "didSeedExamples"

    @MainActor
    static func seedIfNeeded(_ context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: key) else { return }
        for (index, example) in ExampleTemplates.all(DefaultNames.examples).enumerated() {
            context.insert(Template(name: example.name, definition: example.definition, sortIndex: index))
        }
        context.saveOrReport()
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

    private static let keys = ["Full Body", "Legs + Pull-ups", "Home, No Equipment"]

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
        for key in keys {
            let current = Bundle.main.localizedString(forKey: key, value: key, table: nil)
            result[key] = current
            for bundle in bundles {
                result[bundle.localizedString(forKey: key, value: key, table: nil)] = current
            }
        }
        return result
    }
}
