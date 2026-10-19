import Foundation
import SwiftData
import Testing
@testable import TrainingLoop
import TrainingLoopCore

/// Copies two devices made of one built-in exercise or example template merge into one (TECH T13).
@MainActor
struct DeduplicationTests {
    let store: TestStore
    var context: ModelContext { store.context }

    init() throws {
        store = try TestStore()
    }

    /// A built-in exercise as a device creates it on its first launch, on day N.
    @discardableResult
    private func builtin(_ key: String = "barbell_back_squat", createdOn day: Int) throws -> Exercise {
        let exercise = Exercise(builtin: try #require(BuiltinExercises.exercise(key: key)))
        exercise.createdAt = TestStore.date(day)
        context.insert(exercise)
        context.saveOrReport()
        return exercise
    }

    /// An example template as a device creates it on its first launch, on day N.
    @discardableResult
    private func example(_ index: Int, createdOn day: Int) -> Template {
        let example = ExampleTemplates.all(DefaultNames.examples)[index]
        let template = Template(name: example.name, definition: example.definition, sortIndex: index)
        template.exampleKey = example.key
        template.createdAt = TestStore.date(day)
        context.insert(template)
        context.saveOrReport()
        return template
    }

    private var exercises: [Exercise] { (try? context.fetch(FetchDescriptor<Exercise>())) ?? [] }

    private var templates: [Template] {
        (try? context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
    }

    // MARK: Exercises

    @Test func builtinCopiesMergeIntoOldestWithUserChanges() throws {
        let older = try builtin(createdOn: 1)
        let newer = try builtin(createdOn: 2)
        newer.note = "Seat 4"
        newer.isHidden = true
        newer.muscles = [.quads]
        newer.bySide = true
        context.saveOrReport()

        Deduplication.run(context)

        #expect(exercises.count == 1)
        let kept = try #require(exercises.first)
        #expect(kept.createdAt == older.createdAt)
        #expect(kept.note == "Seat 4")
        #expect(kept.isHidden)
        #expect(kept.muscles == [.quads])
        #expect(kept.bySide)
    }

    @Test func differentNotesAreBothKept() throws {
        try builtin(createdOn: 1).note = "Grip wide"
        try builtin(createdOn: 2).note = "Seat 4"

        Deduplication.run(context)

        #expect(exercises.map(\.note) == ["Grip wide\nSeat 4"])
    }

    @Test func differentExercisesStay() throws {
        try builtin("barbell_back_squat", createdOn: 1)
        try builtin("pull_up", createdOn: 2)
        store.exercise("Squat")

        Deduplication.run(context)

        #expect(exercises.count == 3)
    }

    @Test func historyStaysWithMergedExercise() async throws {
        let older = try builtin(createdOn: 1)
        let id = older.id
        try builtin(createdOn: 2)
        await store.addWorkout(on: 3, id, weightKg: 100)

        Deduplication.run(context)

        #expect(exercises.count == 1)
        #expect(context.exerciseWorkouts(id).count == 1)
        #expect(context.hasHistory(try #require(exercises.first)))
    }

    // MARK: Example templates

    @Test func untouchedExampleCopiesMergeIntoOne() throws {
        for index in 0..<3 { example(index, createdOn: 1) }
        let laterFullBody = example(0, createdOn: 2)
        example(1, createdOn: 2)
        example(2, createdOn: 2)
        laterFullBody.lastPerformedAt = TestStore.date(5)
        context.saveOrReport()

        Deduplication.run(context)

        #expect(templates.map(\.exampleKey) == ["fullBody", "legsAndPullUps", "homeNoEquipment"])
        #expect(templates.allSatisfy { $0.createdAt == TestStore.date(1) })
        #expect(templates.first?.lastPerformedAt == TestStore.date(5))
    }

    @Test func editedExampleReplacesUntouchedCopy() async throws {
        let untouched = example(0, createdOn: 1)
        let edited = example(0, createdOn: 2)
        edited.name = "My Full Body"
        let squat = try builtin(createdOn: 1)
        let workout = await store.addWorkout(on: 3, squat.id, weightKg: 80)
        workout.templateID = untouched.id
        context.saveOrReport()

        Deduplication.run(context)

        #expect(templates.map(\.name) == ["My Full Body"])
        #expect(workout.templateID == edited.id)
    }

    @Test func differentlyEditedCopiesAreBothKept() {
        example(0, createdOn: 1).name = "Mon"
        example(0, createdOn: 2).name = "Thu"
        context.saveOrReport()

        Deduplication.run(context)

        #expect(templates.map(\.name) == ["Mon", "Thu"])
    }

    @Test func userTemplatesAreNotMerged() {
        let example = ExampleTemplates.all(DefaultNames.examples)[0]
        for index in 0..<2 {
            context.insert(Template(name: example.name, definition: example.definition, sortIndex: index))
        }
        context.saveOrReport()

        Deduplication.run(context)

        #expect(templates.count == 2)
    }

    // MARK: Names

    @Test func customNamedAlikeGetsFreeName() throws {
        let first = store.exercise("Bench")
        first.createdAt = TestStore.date(1)
        let second = store.exercise("bench")
        second.createdAt = TestStore.date(2)
        context.saveOrReport()

        Deduplication.run(context)

        #expect(first.name == "Bench")
        #expect(second.name == "bench (2)")
    }

    // MARK: Keys for examples made before them

    @Test func untouchedExamplesWithoutKeyGetOne() throws {
        let defaults = try #require(UserDefaults(suiteName: "DeduplicationTests.\(UUID().uuidString)"))
        let examples = ExampleTemplates.all(DefaultNames.examples)
        let untouched = Template(name: examples[0].name, definition: examples[0].definition, sortIndex: 0)
        let renamed = Template(name: "Mine", definition: examples[1].definition, sortIndex: 1)
        var changed = examples[2].definition
        changed.items.removeLast()
        let edited = Template(name: examples[2].name, definition: changed, sortIndex: 2)
        [untouched, renamed, edited].forEach(context.insert)
        context.saveOrReport()

        ExampleKeyMigration.runOnce(context, defaults: defaults)

        #expect(untouched.exampleKey == "fullBody")
        #expect(renamed.exampleKey == nil)
        #expect(edited.exampleKey == nil)
    }
}
