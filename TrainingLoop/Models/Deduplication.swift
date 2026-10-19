import Foundation
import SwiftData
import TrainingLoopCore

/// Merges the copies that two devices made of one thing (TECH T13). Each device creates the built-in
/// exercises and the example templates on its first launch, before iCloud sync (v1.1) brings the other
/// device's rows, and CloudKit allows no unique constraints, so the copies arrive as separate rows.
/// Runs on every launch; with sync on, also after an import. History doesn't change: workouts refer
/// to exercises by `id`, which the copies share.
///
/// Two devices may merge the same copies at once, so the copy kept is chosen by synced values only
/// (the oldest `createdAt`), and both end with the same row.
enum Deduplication {
    @MainActor
    static func run(_ context: ModelContext) {
        mergeExercises(context)
        mergeExampleTemplates(context)
        renameClashingCustoms(context)
        if context.hasChanges { context.saveOrReport() }
    }

    // MARK: Exercises

    /// Rows with one `id`: the built-in exercise each device created. The oldest stays and takes
    /// what the user changed on the others: note, target muscles, sides, hidden, archived.
    @MainActor
    private static func mergeExercises(_ context: ModelContext) {
        let exercises: [Exercise]
        do {
            exercises = try context.fetch(FetchDescriptor<Exercise>())
        } catch {
            Persistence.report("Fetching exercises for merging failed", error)
            return
        }
        for copies in Dictionary(grouping: exercises, by: \.id).values where copies.count > 1 {
            let sorted = copies.sorted(by: isKeptFirst)
            let kept = sorted[0]
            for copy in sorted.dropFirst() {
                merge(copy, into: kept)
                context.delete(copy)
            }
        }
    }

    private static func isKeptFirst(_ a: Exercise, _ b: Exercise) -> Bool {
        if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
        return (a.note, a.musclesRaw.joined(separator: ",")) < (b.note, b.musclesRaw.joined(separator: ","))
    }

    /// A value the user changed beats the catalog's; two different notes are both kept.
    private static func merge(_ copy: Exercise, into kept: Exercise) {
        if kept.note.isEmpty {
            kept.note = copy.note
        } else if !copy.note.isEmpty, copy.note != kept.note {
            kept.note = (kept.note + "\n" + copy.note).cappedNote
        }
        kept.isHidden = kept.isHidden || copy.isHidden
        kept.isArchived = kept.isArchived || copy.isArchived
        guard let builtin = kept.builtin else { return }
        let catalogMuscles = Muscle.ordered(builtin.muscles, primary: builtin.primaryGroup).map(\.rawValue)
        if kept.musclesRaw == catalogMuscles, copy.musclesRaw != catalogMuscles { kept.musclesRaw = copy.musclesRaw }
        if kept.bySide == builtin.bySide, copy.bySide != builtin.bySide { kept.bySide = copy.bySide }
    }

    // MARK: Example templates

    /// Copies of one example: of those alike only the oldest stays, and an untouched example goes
    /// when the user edited another copy of it. Edited copies that differ are all kept: each is the
    /// user's. Workouts started from a removed copy point to the one kept.
    @MainActor
    private static func mergeExampleTemplates(_ context: ModelContext) {
        let templates: [Template]
        do {
            templates = try context.fetch(FetchDescriptor<Template>(predicate: #Predicate { $0.exampleKey != nil }))
        } catch {
            Persistence.report("Fetching example templates for merging failed", error)
            return
        }
        let examples = ExampleTemplates.all(DefaultNames.examples)
        for (key, copies) in Dictionary(grouping: templates, by: { $0.exampleKey ?? "" }) where copies.count > 1 {
            let isUntouched = { (template: Template) in
                DefaultNames.isDefault(template.name, of: key)
                    && examples.first { $0.key == key }?.definition.hasSameContent(as: template.definition) == true
            }
            var kept: [Template] = []
            for copy in copies.sorted(by: { $0.createdAt < $1.createdAt }) {
                if let same = kept.first(where: { isAlike($0, copy) }) {
                    remove(copy, keeping: same, context)
                } else {
                    kept.append(copy)
                }
            }
            guard let edited = kept.first(where: { !isUntouched($0) }) else { continue }
            for untouched in kept where isUntouched(untouched) {
                remove(untouched, keeping: edited, context)
            }
        }
    }

    private static func isAlike(_ a: Template, _ b: Template) -> Bool {
        a.name == b.name && a.definition.hasSameContent(as: b.definition)
    }

    @MainActor
    private static func remove(_ copy: Template, keeping kept: Template, _ context: ModelContext) {
        if let performed = copy.lastPerformedAt, performed > kept.lastPerformedAt ?? .distantPast {
            kept.lastPerformedAt = performed
        }
        let copyID: UUID? = copy.id
        let workouts = (try? context.fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.templateID == copyID }))) ?? []
        for workout in workouts { workout.templateID = kept.id }
        context.delete(copy)
    }

    // MARK: Custom names

    /// Custom exercises that two devices named alike (SPEC D8: names are unique): the newer one
    /// becomes "Name (2)".
    @MainActor
    private static func renameClashingCustoms(_ context: ModelContext) {
        let customs = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.builtinKey == nil }))) ?? []
        guard customs.count > 1 else { return }
        let sorted = customs.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        var taken: [String] = []
        for custom in sorted {
            if ExerciseName.problem(custom.name, otherNames: taken) == .duplicate {
                custom.customName = ExerciseName.copyName(of: custom.name, otherNames: customs.map(\.name))
            }
            taken.append(custom.name)
        }
    }
}
