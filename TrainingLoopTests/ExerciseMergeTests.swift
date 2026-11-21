import Foundation
import SwiftData
import Testing
@testable import TrainingLoop
import TrainingLoopCore

/// Two exercises made one (SPEC D24): history, templates, notes and records move to the kept one.
@MainActor
struct ExerciseMergeTests {
    let store: TestStore
    var context: ModelContext { store.context }

    init() throws {
        store = try TestStore()
    }

    private func builtin() -> Exercise {
        let builtin = BuiltinExercises.all.first { $0.measure == .reps }!
        let exercise = Exercise(builtin: builtin)
        context.insert(exercise)
        context.saveOrReport()
        return exercise
    }

    private func template(_ exerciseID: UUID) -> Template {
        let template = Template(name: "Legs", definition: TestStore.contents(exerciseID, weightKg: 50, reps: 5, sets: 2),
                                sortIndex: 0)
        context.insert(template)
        context.saveOrReport()
        return template
    }

    private func entries(_ id: UUID) -> Int {
        (try? context.fetchCount(FetchDescriptor<WorkoutEntry>(predicate: #Predicate { $0.exerciseID == id }))) ?? -1
    }

    private func sets(_ id: UUID) -> Int {
        (try? context.fetchCount(FetchDescriptor<WorkoutSet>(predicate: #Predicate { $0.exerciseID == id }))) ?? -1
    }

    @Test func customMovesIntoBuiltin() async throws {
        let custom = store.exercise("My Squat")
        custom.note = "Feet wide"
        let catalog = builtin()
        catalog.note = "Slow down"
        let customID = custom.id
        await store.addWorkout(on: 1, customID, weightKg: 60, sets: 3)
        await store.addWorkout(on: 3, catalog.id, weightKg: 50)
        let template = template(customID)

        ExerciseMerge.merge(custom, into: catalog, context: context)
        await RecordRecount.finish()

        #expect(entries(customID) == 0)
        #expect(sets(customID) == 0)
        #expect(entries(catalog.id) == 2)
        #expect(sets(catalog.id) == 4)
        #expect(template.definition.exerciseIDs == [catalog.id])
        #expect(catalog.note == "Slow down\n\nFeet wide")
        let left = try context.fetch(FetchDescriptor<Exercise>())
        #expect(left.map(\.id) == [catalog.id])
        #expect(context.workoutCount(of: catalog) == 2)
    }

    @Test func builtinIsHiddenNotDeleted() async {
        let custom = store.exercise("My Squat")
        let catalog = builtin()
        await store.addWorkout(on: 1, catalog.id, weightKg: 60)

        ExerciseMerge.merge(catalog, into: custom, context: context)
        await RecordRecount.finish()

        #expect(catalog.isHidden)
        #expect(!catalog.isDeleted)
        #expect(entries(catalog.id) == 0)
        #expect(entries(custom.id) == 1)
    }

    @Test func recordsCountOverTheJoinedHistory() async {
        let first = store.exercise("Squat A")
        let second = store.exercise("Squat B")
        let early = await store.addWorkout(on: 1, first.id, weightKg: 60)
        let late = await store.addWorkout(on: 3, second.id, weightKg: 70)
        // Each is the first workout of its exercise: no records yet.
        #expect(early.recordCount == 0)
        #expect(late.recordCount == 0)

        ExerciseMerge.merge(second, into: first, context: context)
        await RecordRecount.finish()

        #expect(early.recordCount == 0)
        #expect(late.recordCount > 0)
    }

    @Test func bothInOneWorkoutKeepRecordsOnFirstEntry() async throws {
        let first = store.exercise("Squat A")
        let second = store.exercise("Squat B")
        await store.addWorkout(on: 1, first.id, weightKg: 50)
        let contents = TemplateDefinition(items: [
            .exercise(TemplateExercise(exerciseID: first.id, sets: [PlannedSet(reps: 5, weightKg: 60)], restSeconds: 90)),
            .exercise(TemplateExercise(exerciseID: second.id, sets: [PlannedSet(reps: 5, weightKg: 65)], restSeconds: 90)),
        ])
        let both = context.saveRecord(nil, name: "Both", note: "", startedAt: TestStore.date(3), durationSeconds: 3600,
                                      contents: contents, original: TemplateDefinition())
        await RecordRecount.finish()

        ExerciseMerge.merge(second, into: first, context: context)
        await RecordRecount.finish()

        let ordered = (both.entries ?? []).sorted { $0.order < $1.order }
        #expect(ordered.map(\.exerciseID) == [first.id, first.id])
        #expect(ordered[0].recordCount > 0)
        #expect(ordered[1].recordCount == 0)
    }

    @Test func differentMeasuresCantMerge() throws {
        let squat = store.exercise("Squat")
        let plank = Exercise(name: "Plank", measure: .time, weighted: false, primaryGroup: .abs, equipment: .bodyweight)
        context.insert(plank)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "TrainingLoopTests.\(UUID().uuidString)")!)
        let controller = WorkoutController(settings: settings, context: context,
                                           fileURL: URL.temporaryDirectory.appending(path: "merge-\(UUID().uuidString).json"))
        #expect(ExerciseMerge.problem(squat, plank, workouts: controller) == .measure)
        #expect(ExerciseMerge.problem(squat, store.exercise("Squat 2"), workouts: controller) == nil)
    }
}
