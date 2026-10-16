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
    /// "Is the workout still going?" is showing (D19).
    var asksIfForgotten = false

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
        // A restored workout keeps its activity: its button may be what woke the app, and a new one
        // can't be requested in the background. Activities of earlier runs go.
        liveActivity.adoptExisting(keep: workout != nil && settings.showOnLockScreen)
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
        begin(fitted(workout, context: context))
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

    /// Every change by the user goes through here: it counts as activity and is saved at once.
    func change(_ edit: (inout ActiveWorkout) -> Void) {
        apply(edit, isActivity: true)
    }

    /// A rest running out is not the user's doing, so it doesn't keep a forgotten workout going (D19).
    private func apply(_ edit: (inout ActiveWorkout) -> Void, isActivity: Bool) {
        guard var workout else { return }
        edit(&workout)
        if isActivity { workout.lastActivityAt = .now }
        self.workout = workout
        persist()
        syncActivity()
    }

    /// Whether the running workout has the exercise: it then keeps its measure and can't be deleted (D8).
    func uses(_ exerciseID: UUID) -> Bool {
        workout?.items.contains { $0.exercises.contains { $0.exerciseID == exerciseID } } ?? false
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
            workout = fitted(workout, context: context)
        }
    }

    func replaceExercise(_ id: UUID, with exerciseID: UUID, context: ModelContext) {
        let previous = context.lastSets(of: [exerciseID])[exerciseID] ?? []
        change { workout in
            workout.replaceExercise(id, with: exerciseID, previous: previous)
            workout = fitted(workout, context: context)
        }
    }

    /// Sets with only what their exercises record (D2): a timed exercise gets no reps from the one it
    /// replaced, an exercise without weight no weight from its history or template.
    private func fitted(_ workout: ActiveWorkout, context: ModelContext) -> ActiveWorkout {
        let ids = Array(Set(workout.items.flatMap(\.exercises).map(\.exerciseID)))
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>(predicate: #Predicate { ids.contains($0.id) }))) ?? []
        let kinds = Dictionary(exercises.map { ($0.id, (measure: $0.measure, weighted: $0.weighted)) },
                               uniquingKeysWith: { first, _ in first })
        var workout = workout
        workout.fitSets { kinds[$0] }
        return workout
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
        // A rest that ran out while the app was frozen is over, not ten seconds longer.
        guard rest.isPaused || rest.endsAt > .now else { return skipRest() }
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
            apply({ $0.rest = nil }, isActivity: false)
            return
        }
        audio.begin()
        restTask = Task { [weak self] in
            for secondsLeft in [3, 2, 1] {
                let cueAt = endsAt.addingTimeInterval(-TimeInterval(secondsLeft))
                // Too late for this one: a short rest or a resume near the end.
                guard cueAt.timeIntervalSinceNow > -0.5 else { continue }
                if cueAt.timeIntervalSinceNow > 0 { try? await Task.sleep(for: .seconds(cueAt.timeIntervalSinceNow)) }
                guard !Task.isCancelled, let self else { return }
                // A frozen app wakes late: a tick for a moment long gone would only puzzle.
                guard Date.now.timeIntervalSince(cueAt) < 1 else { continue }
                self.audio.countdown(secondsLeft)
            }
            let delay = endsAt.timeIntervalSinceNow
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled, let self else { return }
            let onTime = Date.now.timeIntervalSince(endsAt) < 2
            self.apply({ $0.rest = nil }, isActivity: false)
            if onTime { self.audio.restEnded() } else { self.audio.end() }
        }
    }

    /// The app is back in front: restart audio an interruption may have stopped, and bring back an
    /// activity that couldn't be requested in the background or that the system ended.
    func appDidBecomeActive() {
        audio.resumeIfNeeded()
        refreshActivity()
    }

    /// A sample of the chosen set in Settings.
    func previewSound(_ set: SoundSet) {
        audio.preview(set)
    }

    // MARK: Finishing

    /// Asks "Is the workout still going?" when nothing was done for two hours (D19).
    func checkForgotten() {
        guard let workout, Date.now.timeIntervalSince(workout.lastActivityAt) > Self.forgottenAfter else { return }
        asksIfForgotten = true
    }

    /// "Continue": the workout counts as going from now, so the question doesn't come back at once.
    func keepGoing() {
        change { _ in }
        isPresented = true
    }

    /// Writes the ticked sets as a history record (D7, D16). `endedAt` is now, or the last tick for a
    /// forgotten workout (D19). When History is full, the oldest record goes, named on the summary screen.
    /// All in one save: if it fails, the store is rolled back and the workout stays open to try again.
    func save(name: String, note: String, endedAt: Date, updateTemplate: Bool, saveAsTemplate: Bool,
              context: ModelContext) throws {
        guard let active = workout, active.doneSetCount > 0 else { return }
        let oldest = context.oldestWorkoutIfFull()
        let oldestTemplateID = oldest?.templateID
        if let oldest { context.delete(oldest) }
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
        do {
            try context.save()
        } catch {
            context.rollback()
            Persistence.logger.error("Saving the workout failed: \(String(describing: error), privacy: .public)")
            throw error
        }
        if let oldestTemplateID { context.refreshLastPerformed(of: [oldestTemplateID]) }
        end()
        audio.finished()
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
            // Not from the summary: the workout is over and a tick would start a rest.
            guard finishingAt == nil, let workout, let position = workout.nextPosition else { return }
            let measure = exerciseModel(workout.exercise(at: position).exerciseID)?.measure ?? .reps
            guard workout[position].canTick(measure: measure) else { return }
            toggle(workout[position].id)
        case .addRest:
            adjustRest(by: 10)
        case .skipRest:
            skipRest()
        }
    }

    /// After a change in Settings or a return to the app: the lock screen shows the current state.
    func refreshActivity() {
        liveActivity.forgetIfEnded()
        syncActivity()
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
                     supersetNext: supersetNext,
                     canComplete: workout[position].canTick(measure: model?.measure ?? .reps))
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
            // Kept aside, so the next workout doesn't write over what may still be recovered.
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: aside)
            try? FileManager.default.moveItem(at: url, to: aside)
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
            // An exercise done twice in that workout: its entries one after another, not mixed by set number.
            result[id] = sets.filter { $0.workoutStartedAt == latest }
                .sorted { ($0.entry?.order ?? 0, $0.order) < ($1.entry?.order ?? 0, $1.order) }
                .map(\.planned)
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
