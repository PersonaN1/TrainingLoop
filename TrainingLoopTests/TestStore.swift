import Foundation
import SwiftData
@testable import TrainingLoop
import TrainingLoopCore

/// An in-memory store with the app's schema, and helpers to fill it.
@MainActor
struct TestStore {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    /// A weighted exercise on reps.
    func exercise(_ name: String = "Squat") -> Exercise {
        let exercise = Exercise(name: name, measure: .reps, weighted: true, primaryGroup: .quads, equipment: .barbell)
        context.insert(exercise)
        context.saveOrReport()
        return exercise
    }

    /// A finished workout added to History as the record editor does it (D16).
    @discardableResult
    func addWorkout(on day: Int, _ exerciseID: UUID, weightKg: Double, reps: Int = 5, sets: Int = 1) -> Workout {
        context.saveRecord(nil, name: "Day \(day)", note: "", startedAt: Self.date(day), durationSeconds: 3600,
                           contents: Self.contents(exerciseID, weightKg: weightKg, reps: reps, sets: sets),
                           original: TemplateDefinition())
    }

    /// The record editor saving `workout` with new sets and, optionally, a new day.
    func edit(_ workout: Workout, day: Int? = nil, _ exerciseID: UUID, weightKg: Double, reps: Int = 5, sets: Int = 1) {
        context.saveRecord(workout, name: workout.name, note: workout.note,
                           startedAt: day.map(Self.date) ?? workout.startedAt,
                           durationSeconds: workout.durationSeconds,
                           contents: Self.contents(exerciseID, weightKg: weightKg, reps: reps, sets: sets),
                           original: workout.definition)
    }

    static func contents(_ exerciseID: UUID, weightKg: Double, reps: Int, sets: Int) -> TemplateDefinition {
        TemplateDefinition(items: [.exercise(TemplateExercise(
            exerciseID: exerciseID,
            sets: Array(repeating: PlannedSet(reps: reps, weightKg: weightKg), count: sets),
            restSeconds: 90))])
    }

    /// Day N of October 2026, at 18:00 UTC.
    static func date(_ day: Int) -> Date {
        var components = DateComponents(year: 2026, month: 10, day: day, hour: 18)
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}
