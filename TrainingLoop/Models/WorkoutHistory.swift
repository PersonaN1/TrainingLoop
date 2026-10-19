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
        totalVolumeKg = sets.reduce(0) { $0 + $1.planned.volumeKg }
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
                    let row = WorkoutSet(order: index, set, exerciseID: exercise.exerciseID, workoutStartedAt: startedAt)
                    row.completedAt = completedAt
                    entry.sets?.append(row)
                }
                order += 1
            }
        }
        updateTotals()
    }

    /// Without `muscles` the sets aren't counted, and none of them is loaded.
    func facts(muscles: [UUID: ExerciseMuscles]?) -> WorkoutFacts {
        var setsByGroup: [MuscleGroup: Int] = [:]
        var setsByMuscle: [Muscle: Int] = [:]
        if let muscles {
            for entry in entries ?? [] {
                guard let exercise = muscles[entry.exerciseID] else { continue }
                let sets = entry.sets?.count ?? 0
                setsByGroup[exercise.group, default: 0] += sets
                for muscle in exercise.muscles { setsByMuscle[muscle, default: 0] += sets }
            }
        }
        return WorkoutFacts(startedAt: startedAt, durationSeconds: durationSeconds, volumeKg: totalVolumeKg,
                            setsByGroup: setsByGroup, setsByMuscle: setsByMuscle)
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
        RecordRecount.start(entries.map(\.exerciseID), context: context)
        UserDefaults.standard.set(true, forKey: key)
    }
}

/// An exercise's primary group and target muscles, for sets by group and by muscle (SPEC D9).
struct ExerciseMuscles: Sendable {
    var group: MuscleGroup
    var muscles: [Muscle]
}

extension Exercise {
    var groupAndMuscles: ExerciseMuscles { ExerciseMuscles(group: primaryGroup, muscles: muscles) }
}

extension WorkoutSet {
    var planned: PlannedSet {
        PlannedSet(reps: reps, seconds: seconds, weightKg: weightKg,
                   right: bySide ? .init(reps: rightReps, seconds: rightSeconds, weightKg: rightWeightKg) : nil)
    }
}

extension ModelContext {
    func finishedWorkoutCount() -> Int {
        (try? fetchCount(FetchDescriptor<Workout>(predicate: #Predicate { !$0.isActive }))) ?? 0
    }

    /// Deletes workouts with their sets, and moves "last done" on their templates' cards back.
    @MainActor
    func deleteWorkouts(_ workouts: [Workout]) {
        let templateIDs = Set(workouts.compactMap(\.templateID))
        let exerciseIDs = Set(workouts.flatMap { ($0.entries ?? []).map(\.exerciseID) })
        for workout in workouts { delete(workout) }
        // Saved first, so the searches below no longer find them.
        saveOrReport()
        refreshLastPerformed(of: templateIDs)
        RecordRecount.start(exerciseIDs, context: self)
    }

    /// Counts the records of every finished workout with these exercises again (D10, DESIGN V9): a workout
    /// added, changed or deleted moves the records of the ones after it. Call once the change is saved.
    /// Here and now; after a change by the user it runs in the background (`RecordRecount`).
    func refreshRecords(of exerciseIDs: some Sequence<UUID>) {
        applyRecordCounts(recordCountChanges(of: Set(exerciseIDs)))
    }

    /// The entries whose record count differs from a fresh count, with the new count.
    func recordCountChanges(of exerciseIDs: Set<UUID>) -> [PersistentIdentifier: Int] {
        var changes: [PersistentIdentifier: Int] = [:]
        for id in exerciseIDs {
            let workouts = exerciseWorkouts(id)
            let records = PersonalBests.records(of: workouts.map(\.sets))
            for (workout, records) in zip(workouts, records) {
                for (index, entry) in workout.entries.enumerated() {
                    let count = index == 0 ? records.lines.count : 0
                    if entry.recordCount != count { changes[entry.persistentModelID] = count }
                }
            }
        }
        return changes
    }

    /// Writes counts from `recordCountChanges`; an entry deleted meanwhile is skipped.
    func applyRecordCounts(_ changes: [PersistentIdentifier: Int]) {
        for (id, count) in changes {
            guard let entry = model(for: id) as? WorkoutEntry, !entry.isDeleted, entry.recordCount != count else { continue }
            entry.recordCount = count
        }
        if hasChanges { saveOrReport() }
    }

    /// An exercise's finished workouts, oldest first: its entries in each and their sets in order
    /// (records, D10 statistics).
    func exerciseWorkouts(_ exerciseID: UUID) -> [(workout: Workout, entries: [WorkoutEntry], sets: [PlannedSet])] {
        var entryDescriptor = FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == exerciseID })
        entryDescriptor.relationshipKeyPathsForPrefetching = [\.workout]
        guard let entries = try? fetch(entryDescriptor) else { return [] }
        // The sets in one query rather than through each entry: with a long History that is
        // several times faster (TECH T12).
        let setDescriptor = FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseID == exerciseID },
                                                        sortBy: [SortDescriptor(\.order)])
        var setsByEntry: [PersistentIdentifier: [PlannedSet]] = [:]
        for set in (try? fetch(setDescriptor)) ?? [] {
            guard let entry = set.entry else { continue }
            setsByEntry[entry.persistentModelID, default: []].append(set.planned)
        }
        var byWorkout: [PersistentIdentifier: (workout: Workout, entries: [WorkoutEntry])] = [:]
        for entry in entries {
            guard let workout = entry.workout, !workout.isActive else { continue }
            byWorkout[workout.persistentModelID, default: (workout, [])].entries.append(entry)
        }
        return byWorkout.values.sorted { $0.workout.startedAt < $1.workout.startedAt }.map { item in
            let entries = item.entries.sorted { $0.order < $1.order }
            let sets = entries.flatMap { setsByEntry[$0.persistentModelID] ?? [] }
            return (item.workout, entries, sets)
        }
    }

    /// Writes an edited record, or adds a new one to History when `record` is nil (D16). Its sets are
    /// written anew when they changed or the start moved (they repeat it); records and "last done" follow.
    @MainActor @discardableResult
    func saveRecord(_ record: Workout?, name: String, note: String, startedAt: Date, durationSeconds: Int,
                    contents: TemplateDefinition, original: TemplateDefinition) -> Workout {
        let workout: Workout
        if let record {
            workout = record
        } else {
            workout = Workout(name: name, startedAt: startedAt)
            workout.isActive = false
            insert(workout)
        }
        workout.name = name
        workout.note = note
        let start = freeStartTime(startedAt, for: workout)
        let moved = start != workout.startedAt
        workout.startedAt = start
        workout.endedAt = start.addingTimeInterval(TimeInterval(durationSeconds))
        workout.lastActivityAt = workout.endedAt ?? start
        if record == nil || contents != original || moved {
            workout.setContents(contents, context: self)
        }
        saveOrReport()
        if let templateID = workout.templateID { refreshLastPerformed(of: [templateID]) }
        RecordRecount.start(Set(original.exerciseIDs).union(contents.exerciseIDs), context: self)
        return workout
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
