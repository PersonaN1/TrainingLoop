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

    /// "🏆 N" in the history list (DESIGN V9).
    var recordCount: Int {
        (entries ?? []).reduce(0) { $0 + $1.recordCount }
    }

    /// The exercises and sets as a template: what the record editor changes and "Repeat" starts from (D16).
    var definition: TemplateDefinition {
        TemplateDefinition(items: entryGroups.map { group in
            let exercises = group.map { entry in
                TemplateExercise(exerciseID: entry.exerciseID,
                                 sets: (entry.sets ?? []).sorted { $0.order < $1.order }.map(\.planned),
                                 restSeconds: entry.restSeconds)
            }
            guard exercises.count > 1, let first = group.first else { return .exercise(exercises[0]) }
            return .superset(TemplateSuperset(exercises: exercises,
                                              restWithinSeconds: first.restWithinSeconds ?? 0,
                                              restAfterSeconds: first.restAfterSeconds ?? first.restSeconds))
        })
    }

    /// Replaces the exercises and sets with edited ones (D16) and updates the totals.
    /// Records are counted afresh by `refreshRecords` once saved.
    func setContents(_ definition: TemplateDefinition, context: ModelContext) {
        for entry in entries ?? [] { context.delete(entry) }
        entries = []
        let completedAt = endedAt ?? startedAt
        var order = 0
        for (group, item) in definition.items.enumerated() {
            let superset: TemplateSuperset? = if case .superset(let superset) = item { superset } else { nil }
            for exercise in item.exercises {
                let entry = WorkoutEntry(exerciseID: exercise.exerciseID, order: order, restSeconds: exercise.restSeconds)
                entry.supersetGroup = superset == nil ? nil : group
                entry.restWithinSeconds = superset?.restWithinSeconds
                entry.restAfterSeconds = superset?.restAfterSeconds
                entries?.append(entry)
                for (index, set) in exercise.sets.enumerated() {
                    let row = WorkoutSet(order: index, reps: set.reps, seconds: set.seconds, weightKg: set.weightKg,
                                         exerciseID: exercise.exerciseID, workoutStartedAt: startedAt)
                    row.completedAt = completedAt
                    entry.sets?.append(row)
                }
                order += 1
            }
        }
        updateTotals()
    }

    /// Without `groups` the sets aren't counted, and none of them is loaded.
    func facts(groups: [UUID: MuscleGroup]?) -> WorkoutFacts {
        var setsByGroup: [MuscleGroup: Int] = [:]
        if let groups {
            for entry in entries ?? [] {
                guard let group = groups[entry.exerciseID] else { continue }
                setsByGroup[group, default: 0] += entry.sets?.count ?? 0
            }
        }
        return WorkoutFacts(startedAt: startedAt, durationSeconds: durationSeconds, volumeKg: totalVolumeKg,
                            setsByGroup: setsByGroup)
    }
}

/// Workouts saved before records were counted in History get their counts once; the key changes
/// when the counting rules do.
enum RecordCounts {
    private static let key = "recordsCounted.2"

    @MainActor
    static func countOnce(_ context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let entries = (try? context.fetch(FetchDescriptor<WorkoutEntry>())) ?? []
        context.refreshRecords(of: entries.map(\.exerciseID))
        UserDefaults.standard.set(true, forKey: key)
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
        let exerciseIDs = Set(workouts.flatMap { ($0.entries ?? []).map(\.exerciseID) })
        for workout in workouts { delete(workout) }
        // Saved first, so the searches below no longer find them.
        saveOrReport()
        refreshLastPerformed(of: templateIDs)
        refreshRecords(of: exerciseIDs)
    }

    /// Counts the records of every finished workout with these exercises again (D10, DESIGN V9): a workout
    /// added, changed or deleted moves the records of the ones after it. Call once the change is saved.
    func refreshRecords(of exerciseIDs: some Sequence<UUID>) {
        for id in Set(exerciseIDs) {
            let workouts = exerciseWorkouts(id)
            let records = PersonalBests.records(of: workouts.map(\.sets))
            for (workout, records) in zip(workouts, records) {
                for (index, entry) in workout.entries.enumerated() {
                    let count = index == 0 ? records.lines.count : 0
                    if entry.recordCount != count { entry.recordCount = count }
                }
            }
        }
        if hasChanges { saveOrReport() }
    }

    /// An exercise's finished workouts, oldest first: its entries in each and their sets in order
    /// (records, D10 statistics).
    func exerciseWorkouts(_ exerciseID: UUID) -> [(workout: Workout, entries: [WorkoutEntry], sets: [PlannedSet])] {
        let descriptor = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == exerciseID })
        guard let entries = try? fetch(descriptor) else { return [] }
        var byWorkout: [PersistentIdentifier: (workout: Workout, entries: [WorkoutEntry])] = [:]
        for entry in entries {
            guard let workout = entry.workout, !workout.isActive else { continue }
            byWorkout[workout.persistentModelID, default: (workout, [])].entries.append(entry)
        }
        return byWorkout.values.sorted { $0.workout.startedAt < $1.workout.startedAt }.map { item in
            let entries = item.entries.sorted { $0.order < $1.order }
            let sets = entries.flatMap { ($0.sets ?? []).sorted { $0.order < $1.order }.map(\.planned) }
            return (item.workout, entries, sets)
        }
    }

    /// A start time no other workout has: an exercise's history tells workouts apart by it (`recordHistory`).
    func freeStartTime(_ date: Date, for workout: Workout) -> Date {
        var date = date
        while true {
            let start = date
            let others = (try? fetch(FetchDescriptor<Workout>(predicate: #Predicate { $0.startedAt == start }))) ?? []
            guard others.contains(where: { $0 !== workout }) else { return date }
            date = date.addingTimeInterval(1)
        }
    }

    /// "Last done" on the templates' cards, from the workouts left in History.
    func refreshLastPerformed(of templateIDs: Set<UUID>) {
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
