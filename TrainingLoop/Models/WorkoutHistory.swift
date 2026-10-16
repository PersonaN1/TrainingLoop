import Foundation
import SwiftData
import TrainingLoopCore

extension Workout {
    var durationSeconds: Int {
        max(0, Int((endedAt ?? lastActivityAt).timeIntervalSince(startedAt)))
    }

    var orderedEntries: [WorkoutEntry] {
        (entries ?? []).sorted { $0.order < $1.order }
    }

    /// Entries in order, a superset's entries together (DESIGN V4).
    var entryGroups: [[WorkoutEntry]] {
        var groups: [[WorkoutEntry]] = []
        for entry in orderedEntries {
            if let group = entry.supersetGroup, let last = groups.last?.last, last.supersetGroup == group {
                groups[groups.count - 1].append(entry)
            } else {
                groups.append([entry])
            }
        }
        return groups
    }

    /// The cached totals for the history list; call after the sets change.
    func updateTotals() {
        let sets = orderedEntries.flatMap { $0.sets ?? [] }
        totalSets = sets.count
        totalExercises = (entries ?? []).count
        totalVolumeKg = sets.reduce(0) { $0 + WorkoutVolume.of(weightKg: $1.weightKg, reps: $1.reps) }
    }

    func facts(groups: [UUID: MuscleGroup]) -> WorkoutFacts {
        var setsByGroup: [MuscleGroup: Int] = [:]
        for entry in entries ?? [] {
            guard let group = groups[entry.exerciseID] else { continue }
            setsByGroup[group, default: 0] += entry.sets?.count ?? 0
        }
        return WorkoutFacts(startedAt: startedAt, durationSeconds: durationSeconds, volumeKg: totalVolumeKg,
                            setsByGroup: setsByGroup)
    }
}

extension WorkoutSet {
    var planned: PlannedSet { PlannedSet(reps: reps, seconds: seconds, weightKg: weightKg) }
}

extension ModelContext {
    func finishedWorkoutCount() -> Int {
        (try? fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isActive }))) ?? 0
    }

    /// Deletes workouts with their sets, and moves "last done" on their templates' cards back.
    func deleteWorkouts(_ workouts: [Workout]) {
        let templateIDs = Set(workouts.compactMap(\.templateID))
        for workout in workouts { delete(workout) }
        // Saved first, so the search below no longer finds them.
        saveOrReport()
        for id in templateIDs {
            var latest = FetchDescriptor<Workout>(predicate: #Predicate { $0.templateID == id && !$0.isActive },
                                                  sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
            latest.fetchLimit = 1
            let template = try? fetch(FetchDescriptor<Template>(predicate: #Predicate { $0.id == id })).first
            template?.lastPerformedAt = (try? fetch(latest))?.first?.startedAt
        }
        if hasChanges { saveOrReport() }
    }
}
