import Foundation
import Observation
import SwiftData
import TrainingLoopCore

/// The workout in progress (TECH T5, T6): one at a time, saved to a file after every action so it survives
/// the app being closed (SPEC D19), turned into a history record on "Save".
/// The end of a rest is signalled by sound, voice and vibration (T7); the lock screen shows a Live Activity (T8).
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

    /// Earlier workouts of the exercises in this one, for the records (D10); loaded as exercises come in.
    private var history: [UUID: [[PlannedSet]]] = [:]

    private let settings: AppSettings
    private let fileURL: URL
    /// Exercise names for the Live Activity; nil in previews, which then stay off the lock screen.
    private let context: ModelContext?
    private var restTask: Task<Void, Never>?
    private let audio: WorkoutAudio
    private let liveActivity = LiveActivityManager()

    init(settings: AppSettings, context: ModelContext? = nil, fileURL: URL = WorkoutController.defaultFileURL) {
        self.settings = settings
        self.context = context
        self.fileURL = fileURL
        audio = WorkoutAudio(settings: settings)
        workout = Self.load(from: fileURL)
        guard context != nil else { return }
        // The lock screen buttons reach the workout through here, even when they woke the app.
        WorkoutCommands.handler = { [weak self] in self?.perform($0) }
        WorkoutCommands.flush = { [weak self] in await self?.liveActivity.flush() }
        // A workout restored after the app was closed gets its activity back; a stale one goes.
        LiveActivityManager.endExisting()
        syncActivity()
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
        syncActivity()
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
        syncActivity()
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

    // MARK: Records (D10)

    /// Records against the history loaded so far; an exercise not loaded yet has none.
    var records: WorkoutRecords {
        workout?.records(history: history) ?? WorkoutRecords()
    }

    func loadHistory(context: ModelContext) {
        guard let workout else { return }
        let missing = workout.items.flatMap(\.exercises).map(\.exerciseID).filter { history[$0] == nil }
        guard !missing.isEmpty else { return }
        history.merge(context.recordHistory(of: missing)) { $1 }
    }

    // MARK: Rest (TECH T6)

    var rest: ActiveWorkout.Rest? { workout?.rest }

    func startRest(seconds: Int) {
        change { $0.rest = .init(endsAt: .now.addingTimeInterval(TimeInterval(seconds)), totalSeconds: seconds) }
        scheduleRestEnd()
    }

    /// "+10 / −10": moves the end; below zero the rest is over.
    func adjustRest(by seconds: Int) {
        guard var rest else { return }
        let left = rest.left(at: .now) + TimeInterval(seconds)
        if left <= 0 {
            skipRest()
            return
        }
        if rest.isPaused {
            rest.pausedLeft = left
        } else {
            rest.endsAt = .now.addingTimeInterval(left)
        }
        rest.totalSeconds = max(1, rest.totalSeconds + seconds)
        change { $0.rest = rest }
        scheduleRestEnd()
    }

    /// The pause stops the countdown only; the workout time runs on (D19).
    func toggleRestPause() {
        guard var rest else { return }
        if let left = rest.pausedLeft {
            rest.endsAt = .now.addingTimeInterval(left)
            rest.pausedLeft = nil
        } else {
            rest.pausedLeft = rest.left(at: .now)
        }
        change { $0.rest = rest }
        scheduleRestEnd()
    }

    func skipRest() {
        restTask?.cancel()
        audio.end()
        change { $0.rest = nil }
    }

    /// Plays the 3-2-1 and, at the end, clears the rest and signals it. The audio session is held
    /// only while a rest runs (T6), which keeps the app awake on the lock screen for the signals.
    private func scheduleRestEnd() {
        restTask?.cancel()
        guard let rest, !rest.isPaused else {
            audio.end()
            return
        }
        let endsAt = rest.endsAt
        // A rest that ended while the app was closed is cleared without a late signal.
        guard endsAt.timeIntervalSinceNow > -2 else {
            change { $0.rest = nil }
            return
        }
        audio.begin()
        restTask = Task { [weak self] in
            for secondsLeft in [3, 2, 1] {
                let delay = endsAt.addingTimeInterval(-TimeInterval(secondsLeft)).timeIntervalSinceNow
                // Too late for this one: a short rest or a resume near the end.
                guard delay > -0.5 else { continue }
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled, let self else { return }
                self.audio.countdown(secondsLeft)
            }
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            self.change { $0.rest = nil }
            self.audio.restEnded()
        }
    }

    /// The app is back in front: restart audio an interruption may have stopped.
    func appDidBecomeActive() {
        audio.resumeIfNeeded()
    }

    /// A sample of the chosen set in Settings.
    func previewSound(_ set: SoundSet) {
        audio.preview(set)
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
        audio.finished()
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
        audio.end()
        liveActivity.end()
        workout = nil
        history = [:]
        finishingAt = nil
        isPresented = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: Lock screen (TECH T8)

    /// The buttons on the Live Activity.
    private func perform(_ command: WorkoutCommand) {
        switch command {
        case .completeSet:
            guard let workout, let position = workout.nextPosition, workout[position].value.hasValue else { return }
            toggle(workout[position].id)
        case .addRest:
            adjustRest(by: 10)
        case .skipRest:
            skipRest()
        }
    }

    /// Starts, updates or ends the activity to match the workout and the setting.
    private func syncActivity() {
        guard context != nil else { return }
        guard let workout, settings.showOnLockScreen else {
            liveActivity.end()
            return
        }
        let state = activityState(of: workout)
        if liveActivity.isRunning {
            liveActivity.update(state)
        } else {
            liveActivity.start(.init(workoutName: workout.name, startedAt: workout.startedAt), state: state)
        }
    }

    private func activityState(of workout: ActiveWorkout) -> WorkoutActivityAttributes.ContentState {
        let rest = workout.rest.map { rest in
            WorkoutActivityAttributes.ContentState.Rest(
                start: rest.endsAt.addingTimeInterval(-TimeInterval(rest.totalSeconds)),
                end: rest.endsAt, pausedLeft: rest.pausedLeft)
        }
        guard let position = workout.nextPosition else {
            return .init(rest: rest, exerciseName: nil, setNumber: 0, setCount: 0, plan: "",
                         supersetNext: nil, canComplete: false)
        }
        let exercise = workout.exercise(at: position)
        let model = exerciseModel(exercise.exerciseID)
        let value = workout[position].value
        // In a superset the set after this one is the next exercise of the round.
        let order = workout.order
        let later = order.drop { $0 != position }.dropFirst()
        var supersetNext: String?
        if workout.items[position.item].isSuperset,
           let next = later.first(where: { $0.item == position.item && !workout[$0].isDone }),
           next.exercise != position.exercise {
            let name = exerciseModel(workout.exercise(at: next).exerciseID)?.name ?? ""
            supersetNext = String(localized: "Superset · next \(name)")
        }
        return .init(rest: rest, exerciseName: model?.name ?? String(localized: "Exercise"),
                     setNumber: position.set + 1, setCount: exercise.sets.count,
                     plan: planText(value, weighted: model?.weighted ?? true),
                     supersetNext: supersetNext, canComplete: value.hasValue)
    }

    /// "62.5 kg × 8", "× 12", "45 s".
    private func planText(_ value: PlannedSet, weighted: Bool) -> String {
        if let seconds = value.seconds { return String(localized: "\(seconds) s") }
        guard let reps = value.reps else {
            return value.weightKg.map(settings.weightUnit.weightText) ?? ""
        }
        if weighted, let weight = value.weightKg { return "\(settings.weightUnit.weightText(weight)) × \(reps)" }
        return "× \(reps)"
    }

    private func exerciseModel(_ id: UUID) -> Exercise? {
        try? context?.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { $0.id == id })).first
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

    /// Each exercise's earlier workouts, for records (D10): one array of sets per workout.
    func recordHistory(of exerciseIDs: [UUID]) -> [UUID: [[PlannedSet]]] {
        var result: [UUID: [[PlannedSet]]] = [:]
        for id in Set(exerciseIDs) {
            let descriptor = FetchDescriptor<WorkoutSet>(
                predicate: #Predicate { $0.exerciseID == id },
                sortBy: [SortDescriptor(\.workoutStartedAt), SortDescriptor(\.order)])
            guard let sets = try? fetch(descriptor) else { continue }
            var workouts: [Date: [PlannedSet]] = [:]
            for set in sets { workouts[set.workoutStartedAt, default: []].append(set.planned) }
            result[id] = workouts.sorted { $0.key < $1.key }.map(\.value)
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
