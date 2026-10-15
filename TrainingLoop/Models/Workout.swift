import Foundation
import SwiftData

/// A performed workout, stored as rows so statistics can query sets directly (TECH T2, ADR 0001).
@Model
final class Workout {
    var id: UUID = UUID()
    var name: String = ""
    var note: String = ""
    var startedAt: Date = Date.now
    var endedAt: Date?
    /// Last mark or edit; finds a forgotten workout (SPEC D19).
    var lastActivityAt: Date = Date.now
    var isActive: Bool = false
    /// The template it started from, for "Update template"; nil for a free workout.
    var templateID: UUID?
    // Totals cached for the history list.
    var totalVolumeKg: Double = 0
    var totalSets: Int = 0
    var totalExercises: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \WorkoutEntry.workout)
    var entries: [WorkoutEntry]? = []

    init(name: String, startedAt: Date = .now, templateID: UUID? = nil) {
        self.name = name
        self.startedAt = startedAt
        self.lastActivityAt = startedAt
        self.templateID = templateID
        self.isActive = true
    }
}

/// One exercise in a workout.
@Model
final class WorkoutEntry {
    var workout: Workout?
    var exerciseID: UUID = UUID()
    var order: Int = 0
    /// Entries with the same number form a superset; nil outside one.
    var supersetGroup: Int?
    var restSeconds: Int = 0
    var restWithinSeconds: Int?
    var restAfterSeconds: Int?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.entry)
    var sets: [WorkoutSet]? = []

    init(exerciseID: UUID, order: Int, restSeconds: Int) {
        self.exerciseID = exerciseID
        self.order = order
        self.restSeconds = restSeconds
    }
}

/// One completed set. `exerciseID` and `workoutStartedAt` repeat the entry's and workout's values,
/// so "all sets of an exercise by date" is one predicate query; keep them in sync on edits.
@Model
final class WorkoutSet {
    var entry: WorkoutEntry?
    var order: Int = 0
    var reps: Int?
    var seconds: Int?
    /// Always kilograms, unrounded; pounds are for input and display only (SPEC D15).
    var weightKg: Double?
    var completedAt: Date = Date.now
    var exerciseID: UUID = UUID()
    var workoutStartedAt: Date = Date.now

    init(order: Int, reps: Int? = nil, seconds: Int? = nil, weightKg: Double? = nil,
         exerciseID: UUID, workoutStartedAt: Date) {
        self.order = order
        self.reps = reps
        self.seconds = seconds
        self.weightKg = weightKg
        self.exerciseID = exerciseID
        self.workoutStartedAt = workoutStartedAt
    }
}
