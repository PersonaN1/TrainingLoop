import Foundation
import Observation
import SwiftData
import TrainingLoopCore
import UIKit

/// The workout in progress (TECH T5, T6): one at a time, saved to a file after every action so it survives
/// the app being closed (SPEC D19), turned into a history record on "Save".
/// Sounds and the Live Activity come next; for now the end of a rest is a vibration.
@MainActor
@Observable
final class WorkoutController {
    private(set) var workout: ActiveWorkout?
    /// The workout screen is open; when false a running workout shows as a bar above the tabs.
    var isPresented = false
    /// The summary screen is showing, with this end time (SPEC D11, D19).
    var finishingAt: Date?
    /// A workout untouched for this long asks whether it is still going (D19).
    static let forgottenAfter: TimeInterval = 2 * 60 * 60

    private let settings: AppSettings
    private let fileURL: URL
    private var restTask: Task<Void, Never>?

    init(settings: AppSettings, fileURL: URL = WorkoutController.defaultFileURL) {
        self.settings = settings
        self.fileURL = fileURL
        workout = Self.load(from: fileURL)
        scheduleRestEnd()
    }

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "active-workout.json")
    }

    // MARK: Starting

    func start(_ template: Template, context: ModelContext) {
        let definition = template.definition
        let workout = ActiveWorkout(template: definition, name: template.name, templateID: template.id,
                                    startedAt: .now, previous: context.lastSets(of: definition.exerciseIDs))
        begin(workout)
    }

    func startFree() {
        begin(ActiveWorkout(name: String(localized: "Free Workout"), startedAt: .now))
    }

    private func begin(_ workout: ActiveWorkout) {
        guard self.workout == nil else {
            isPresented = true
            return
        }
        self.workout = workout
        persist()
        isPresented = true
    }

    // MARK: Changing

    /// Every change goes through here: it counts as activity and is saved at once.
    func change(_ edit: (inout ActiveWorkout) -> Void) {
        guard var workout else { return }
        edit(&workout)
        workout.lastActivityAt = .now
        self.workout = workout
        persist()
    }

    /// The tick (D7): records the shown values and starts the rest when there is a set to rest for (D5).
    func toggle(_ setID: UUID) {
        guard let workout, let position = workout.position(of: setID) else { return }
        if workout[position].isDone {
            change { $0.updateSet(setID) { $0.doneAt = nil } }
            return
        }
        let rest = workout.restSeconds(after: position)
        change { workout in
            workout.updateSet(setID) { set in
                set.entered = set.value
                set.doneAt = .now
            }
        }
        if settings.autoStartRest, rest > 0, self.workout?.nextPosition != nil {
            startRest(seconds: rest)
        }
    }

    func addExercises(_ exerciseIDs: [UUID], context: ModelContext) {
        let previous = context.lastSets(of: exerciseIDs)
        change { workout in
            for id in exerciseIDs {
                workout.items.append(.exercise(ActiveWorkout.newExercise(
                    id, restSeconds: settings.defaultRestSeconds, previous: previous[id] ?? [])))
            }
        }
    }

    func replaceExercise(_ id: UUID, with exerciseID: UUID, context: ModelContext) {
        let previous = context.lastSets(of: [exerciseID])[exerciseID] ?? []
        change { $0.replaceExercise(id, with: exerciseID, previous: previous) }
    }

    // MARK: Rest (TECH T6)

    var rest: ActiveWorkout.Rest? { workout?.rest }

    func startRest(seconds: Int) {
        change { $0.rest = .init(endsAt: .now.addingTimeInterval(TimeInterval(seconds)), totalSeconds: seconds) }
        scheduleRestEnd()
    }

    /// "+10 / −10": moves the end; below zero the rest is over.
    func adjustRest(by seconds: Int) {
        guard let rest else { return }
        let endsAt = rest.endsAt.addingTimeInterval(TimeInterval(seconds))
        if endsAt <= .now {
            skipRest()
            return
        }
        change { $0.rest = .init(endsAt: endsAt, totalSeconds: max(1, rest.totalSeconds + seconds)) }
        scheduleRestEnd()
    }

    func skipRest() {
        restTask?.cancel()
        change { $0.rest = nil }
    }

    /// Sleeps until the end, then clears the rest and signals it.
    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let endsAt = rest?.endsAt else { return }
        restTask = Task { [weak self] in
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.change { $0.rest = nil }
            if self.settings.vibration {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    // MARK: Finishing

    var isForgotten: Bool {
        guard let workout else { return false }
        return Date.now.timeIntervalSince(workout.lastActivityAt) > Self.forgottenAfter
    }

    /// Writes the ticked sets as a history record (D7, D16). `endedAt` is now, or the last tick for a
    /// forgotten workout (D19). When History is full, the oldest record goes first, named on the summary screen.
    @discardableResult
    func save(name: String, note: String, endedAt: Date, updateTemplate: Bool, saveAsTemplate: Bool,
              context: ModelContext) -> Workout? {
        guard let active = workout else { return nil }
        if let oldest = context.oldestWorkoutIfFull() {
            context.deleteWorkouts([oldest])
        }
        let record = Workout(name: name, startedAt: active.startedAt, templateID: active.templateID)
        record.isActive = false
        record.note = note
        record.endedAt = endedAt
        record.lastActivityAt = endedAt
        context.insert(record)
        var order = 0
        for (group, item) in active.doneItems.enumerated() {
            let superset: ActiveWorkout.Superset? = if case .superset(let superset) = item { superset } else { nil }
            for exercise in item.exercises {
                let entry = WorkoutEntry(exerciseID: exercise.exerciseID, order: order, restSeconds: exercise.restSeconds)
                entry.supersetGroup = superset == nil ? nil : group
                entry.restWithinSeconds = superset?.restWithinSeconds
                entry.restAfterSeconds = superset?.restAfterSeconds
                record.entries?.append(entry)
                for (index, set) in exercise.sets.enumerated() {
                    let row = WorkoutSet(order: index, reps: set.value.reps, seconds: set.value.seconds,
                                         weightKg: set.value.weightKg, exerciseID: exercise.exerciseID,
                                         workoutStartedAt: active.startedAt)
                    row.completedAt = set.doneAt ?? endedAt
                    entry.sets?.append(row)
                }
                order += 1
            }
        }
        record.updateTotals()
        if let id = active.templateID,
           let template = try? context.fetch(FetchDescriptor<Template>(predicate: #Predicate { $0.id == id })).first {
            template.lastPerformedAt = max(template.lastPerformedAt ?? .distantPast, active.startedAt)
            if updateTemplate { template.definition = active.asTemplate }
        } else if saveAsTemplate {
            var last = FetchDescriptor<Template>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
            last.fetchLimit = 1
            let sortIndex = ((try? context.fetch(last))?.first?.sortIndex ?? -1) + 1
            let template = Template(name: name, definition: active.asTemplate, sortIndex: sortIndex)
            template.lastPerformedAt = active.startedAt
            context.insert(template)
        }
        context.saveOrReport()
        end()
        return record
    }

    /// "Finish": the summary, timed to now.
    func finish() {
        finishingAt = .now
    }

    /// "Finish" for a forgotten workout: its length runs to the last tick (D19).
    func finishForgotten() {
        finishingAt = workout?.lastMarkAt
        isPresented = true
    }

    /// "Don't save": the workout is gone.
    func discard() {
        end()
    }

    private func end() {
        restTask?.cancel()
        workout = nil
        finishingAt = nil
        isPresented = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: File

    private func persist() {
        guard let workout else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(workout).write(to: fileURL, options: .atomic)
        } catch {
            Persistence.report("Saving the workout in progress failed", error)
        }
    }

    private static func load(from url: URL) -> ActiveWorkout? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try JSONDecoder().decode(ActiveWorkout.self, from: data)
        } catch {
            Persistence.logger.error("The workout in progress can't be read: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

extension ModelContext {
    /// Each exercise's sets from the last workout that had it, by any template (D7).
    func lastSets(of exerciseIDs: [UUID]) -> [UUID: [PlannedSet]] {
        var result: [UUID: [PlannedSet]] = [:]
        for id in Set(exerciseIDs) {
            var descriptor = FetchDescriptor<WorkoutSet>(
                predicate: #Predicate { $0.exerciseID == id },
                sortBy: [SortDescriptor(\.workoutStartedAt, order: .reverse), SortDescriptor(\.order)])
            descriptor.fetchLimit = 60
            guard let sets = try? fetch(descriptor), let latest = sets.first?.workoutStartedAt else { continue }
            result[id] = sets.filter { $0.workoutStartedAt == latest }.map(\.planned)
        }
        return result
    }

    /// The record "Save" would remove at the History limit (D16), or nil while there is room.
    func oldestWorkoutIfFull() -> Workout? {
        guard finishedWorkoutCount() >= Limits.maxWorkouts else { return nil }
        var oldest = FetchDescriptor<Workout>(predicate: #Predicate { !$0.isActive },
                                              sortBy: [SortDescriptor(\.startedAt)])
        oldest.fetchLimit = 1
        return try? fetch(oldest).first
    }
}
