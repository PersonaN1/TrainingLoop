import Foundation
import SwiftData
import Testing
@testable import TrainingLoop
import TrainingLoopCore

/// "Save" on the summary turns the workout in progress into a History record (D7, D16).
@MainActor
struct SavingWorkoutTests {
    let store: TestStore
    let controller: WorkoutController
    let fileURL = URL.temporaryDirectory.appending(path: "workout-\(UUID().uuidString).json")

    init() throws {
        store = try TestStore()
        let settings = AppSettings(defaults: UserDefaults(suiteName: "TrainingLoopTests.\(UUID().uuidString)")!)
        settings.showOnLockScreen = false
        settings.autoStartRest = false
        settings.soundSet = nil
        controller = WorkoutController(settings: settings, context: store.context, fileURL: fileURL)
    }

    private func template(_ exerciseID: UUID, weightKg: Double) -> Template {
        let template = Template(name: "Legs", definition: TestStore.contents(exerciseID, weightKg: weightKg, reps: 5, sets: 3),
                                sortIndex: 0)
        store.context.insert(template)
        store.context.saveOrReport()
        return template
    }

    /// Ticks the first `count` sets and saves the workout an hour after it started.
    private func tickAndSave(_ count: Int, note: String = "") throws {
        let sets = try #require(controller.workout).items[0].exercises[0].sets
        for set in sets.prefix(count) { controller.toggle(set.id) }
        let startedAt = try #require(controller.workout).startedAt
        try controller.save(name: "Legs", note: note, endedAt: startedAt.addingTimeInterval(3600),
                            updateTemplate: false, saveAsTemplate: false, context: store.context)
    }

    @Test func savesTickedSetsAsRecord() throws {
        let squat = store.exercise()
        let template = template(squat.id, weightKg: 60)
        controller.start(template, context: store.context)
        #expect(controller.workout != nil)

        controller.toggle(try #require(controller.workout).items[0].exercises[0].sets[0].id)
        // Saved after every action, so it survives the app being closed (D19).
        #expect(FileManager.default.fileExists(atPath: fileURL.path()))
        let startedAt = try #require(controller.workout).startedAt
        try controller.save(name: "Legs", note: "Felt good", endedAt: startedAt.addingTimeInterval(3600),
                            updateTemplate: false, saveAsTemplate: false, context: store.context)

        #expect(controller.workout == nil)
        #expect(!FileManager.default.fileExists(atPath: fileURL.path()))
        let records = try store.context.fetch(FetchDescriptor<Workout>())
        let record = try #require(records.first)
        #expect(records.count == 1)
        #expect(!record.isActive)
        #expect(record.name == "Legs")
        #expect(record.note == "Felt good")
        #expect(record.templateID == template.id)
        #expect(record.durationSeconds == 3600)
        // Only the ticked set is history.
        #expect(record.totalSets == 1)
        #expect(record.totalExercises == 1)
        #expect(record.totalVolumeKg == 300)
        let set = try #require(record.orderedEntries.first?.sets?.first)
        #expect(set.planned == PlannedSet(reps: 5, weightKg: 60))
        #expect(set.exerciseID == squat.id)
        #expect(set.workoutStartedAt == record.startedAt)
        #expect(template.lastPerformedAt == record.startedAt)
        // A first workout has nothing to beat.
        #expect(record.recordCount == 0)
    }

    @Test func heavierWorkoutCountsRecords() throws {
        let squat = store.exercise()
        controller.start(template(squat.id, weightKg: 60), context: store.context)
        try tickAndSave(3)
        controller.start(template(squat.id, weightKg: 70), context: store.context)
        try tickAndSave(3)

        let records = try store.context.fetch(FetchDescriptor<Workout>(sortBy: [SortDescriptor(\.startedAt)]))
        #expect(records.count == 2)
        #expect(records.last?.recordCount ?? 0 > 0)
        #expect(records.first?.recordCount == 0)
    }

    @Test func nothingTickedSavesNothing() throws {
        let squat = store.exercise()
        controller.start(template(squat.id, weightKg: 60), context: store.context)
        try tickAndSave(0)
        #expect(try store.context.fetchCount(FetchDescriptor<Workout>()) == 0)
        // The workout stays open: there was nothing to save.
        #expect(controller.workout != nil)
    }
}
