#if DEBUG
import Foundation
import SwiftData
import TrainingLoopCore

/// Debug builds only: ten weeks of workouts from the templates, for working on History before
/// workouts can be recorded. Launch with `-SampleHistory YES`; does nothing once History has workouts.
enum SampleHistory {
    @MainActor
    static func insertIfRequested(_ context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "SampleHistory"), context.finishedWorkoutCount() == 0,
              let templates = try? context.fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\.sortIndex)])),
              !templates.isEmpty,
              let exercises = try? context.fetch(FetchDescriptor<Exercise>())
        else { return }
        let byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        var number = 0
        for daysAgo in stride(from: 70, through: 0, by: -1) where daysAgo % 7 == 1 || daysAgo % 7 == 3 || daysAgo % 7 == 5 {
            guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                  let start = calendar.date(bySettingHour: 18, minute: 5 * (number % 6), second: 0, of: day)
            else { continue }
            let template = templates[number % templates.count]
            insert(template, startedAt: start, progress: Double(70 - daysAgo) / 70, exercises: byID, into: context)
            number += 1
        }
        context.saveOrReport()
        context.refreshRecords(of: exercises.map(\.id))
    }

    @MainActor
    private static func insert(_ template: Template, startedAt: Date, progress: Double,
                               exercises: [UUID: Exercise], into context: ModelContext) {
        let definition = template.definition
        let workout = Workout(name: template.name, startedAt: startedAt, templateID: template.id)
        workout.isActive = false
        workout.endedAt = startedAt.addingTimeInterval(TimeInterval(definition.estimatedSeconds))
        context.insert(workout)
        var order = 0
        for (groupIndex, item) in definition.items.enumerated() {
            for planned in item.exercises {
                let entry = WorkoutEntry(exerciseID: planned.exerciseID, order: order, restSeconds: planned.restSeconds)
                entry.supersetGroup = item.isSuperset ? groupIndex : nil
                workout.entries?.append(entry)
                let exercise = exercises[planned.exerciseID]
                let weight = exercise.flatMap { baseWeight($0, progress: progress) }
                for (index, set) in planned.sets.enumerated() {
                    entry.sets?.append(WorkoutSet(order: index, reps: set.reps, seconds: set.seconds, weightKg: weight,
                                                  exerciseID: planned.exerciseID, workoutStartedAt: startedAt))
                }
                order += 1
            }
        }
        workout.updateTotals()
        template.lastPerformedAt = max(template.lastPerformedAt ?? .distantPast, startedAt)
    }

    /// Barbell work grows from 40 to 60 kg over the ten weeks; bodyweight work has no weight.
    private static func baseWeight(_ exercise: Exercise, progress: Double) -> Double? {
        guard exercise.weighted, exercise.measure == .reps, exercise.equipment != .bodyweight else { return nil }
        return ((40 + 20 * progress) * 2).rounded() / 2
    }
}
#endif
