#if DEBUG
import Foundation
import SwiftData
import TrainingLoopCore

/// Debug builds only: ten weeks of workouts from the templates, for working on History before
/// workouts can be recorded. Launch with `-SampleHistory YES`; does nothing once History has workouts.
/// `-FullHistory YES` fills History to the limit instead, for checking speed (TECH T12).
enum SampleHistory {
    @MainActor
    static func insertIfRequested(_ context: ModelContext) {
        if UserDefaults.standard.bool(forKey: "FullHistory"), context.finishedWorkoutCount() == 0 {
            let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            let weighted = exercises.filter { $0.weighted && $0.measure == .reps }.sorted { $0.name < $1.name }
            insertFull(Array(weighted.prefix(20)).map(\.id), into: context)
            RecordRecount.start(weighted.map(\.id), context: context)
            return
        }
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

    /// `Limits.maxWorkouts` workouts (≈ 60k sets), one a day back from yesterday: five of the exercises
    /// in turn, four sets each, weights rising and falling. Record counts are left to the caller.
    static func insertFull(_ exerciseIDs: [UUID], into context: ModelContext,
                           count: Int = Limits.maxWorkouts) {
        guard !exerciseIDs.isEmpty else { return }
        let perWorkout = min(5, exerciseIDs.count)
        let today = Calendar.current.startOfDay(for: .now)
        for number in 0..<count {
            let daysAgo = count - number
            let start = today.addingTimeInterval(TimeInterval(-daysAgo * 86_400 + 18 * 3600))
            let workout = Workout(name: "Workout \(number % 3 + 1)", startedAt: start)
            workout.isActive = false
            workout.endedAt = start.addingTimeInterval(3600)
            context.insert(workout)
            for order in 0..<perWorkout {
                let exerciseID = exerciseIDs[(number + order * 4) % exerciseIDs.count]
                let entry = WorkoutEntry(exerciseID: exerciseID, order: order, restSeconds: 90)
                workout.entries?.append(entry)
                let weight = 40 + Double(number % 400) / 10
                for index in 0..<4 {
                    entry.sets?.append(WorkoutSet(order: index, reps: 8 - index, weightKg: weight,
                                                  exerciseID: exerciseID, workoutStartedAt: start))
                }
            }
            workout.updateTotals()
            if number % 250 == 249 { context.saveOrReport() }
        }
        context.saveOrReport()
    }

    /// Barbell work grows from 40 to 60 kg over the ten weeks; bodyweight work has no weight.
    private static func baseWeight(_ exercise: Exercise, progress: Double) -> Double? {
        guard exercise.weighted, exercise.measure == .reps, exercise.equipment != .bodyweight else { return nil }
        return ((40 + 20 * progress) * 2).rounded() / 2
    }
}
#endif
