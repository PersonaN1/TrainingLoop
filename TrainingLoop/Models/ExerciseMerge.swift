import Foundation
import SwiftData
import TrainingLoopCore

/// Two exercises made one (SPEC D24): a custom exercise and the same one from the catalog, or two
/// custom copies. History, templates and records of the other move to the kept one.
@MainActor
enum ExerciseMerge {
    enum Problem: Equatable {
        /// Reps and time can't share a history.
        case measure
        /// The running workout lives in a file with its own exercise IDs; finish it first.
        case inWorkout
    }

    static func problem(_ first: Exercise, _ second: Exercise, workouts: WorkoutController) -> Problem? {
        if first.measure != second.measure { return .measure }
        if workouts.uses(first.id) || workouts.uses(second.id) { return .inWorkout }
        return nil
    }

    /// Moves everything of `other` to `kept`, then removes `other`: a custom exercise is deleted,
    /// a built-in one is hidden (the catalog would bring it back). Records are counted again.
    static func merge(_ other: Exercise, into kept: Exercise, context: ModelContext) {
        let oldID = other.id, newID = kept.id
        guard oldID != newID else { return }

        let entries = (try? context.fetch(FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == oldID }))) ?? []
        for entry in entries { entry.exerciseID = newID }
        // Sets repeat the entry's exercise for one-query statistics (`WorkoutSet`).
        let sets = (try? context.fetch(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseID == oldID }))) ?? []
        for set in sets { set.exerciseID = newID }

        for template in (try? context.fetch(FetchDescriptor<Template>())) ?? []
        where template.definition.exerciseIDs.contains(oldID) {
            template.definition = template.definition.replacingExerciseID(oldID, with: newID)
        }

        let note = other.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty, !kept.note.contains(note) {
            kept.note = (kept.note.isEmpty ? note : kept.note + "\n\n" + note).cappedNote
        }

        if other.isCustom {
            context.delete(other)
        } else {
            other.isHidden = true
        }
        context.saveOrReport()
        RecordRecount.start([newID], context: context)
    }
}

extension ModelContext {
    /// Finished workouts with the exercise, for the merge dialog.
    func workoutCount(of exercise: Exercise) -> Int {
        let id = exercise.id
        var descriptor = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == id })
        descriptor.relationshipKeyPathsForPrefetching = [\.workout]
        let entries = (try? fetch(descriptor)) ?? []
        return Set(entries.compactMap { entry in
            entry.workout.flatMap { $0.isActive ? nil : $0.persistentModelID }
        }).count
    }
}
