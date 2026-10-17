#if DEBUG
import Foundation
import SwiftData
import TrainingLoopCore

/// Debug builds only: ten weeks of workouts from the templates, for working on History and for the
/// App Store screenshots (docs/APPSTORE.md). Launch with `-SampleHistory YES`; does nothing once History has workouts.
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
            insert(template, startedAt: start, progress: Double(70 - daysAgo) / 70, lightDay: number % 7 == 4,
                   exercises: byID, into: context)
            number += 1
        }
        context.saveOrReport()
        context.refreshRecords(of: exercises.map(\.id))
    }

    @MainActor
    private static func insert(_ template: Template, startedAt: Date, progress: Double, lightDay: Bool,
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
                let key = exercises[planned.exerciseID]?.builtinKey
                let weight = key.flatMap { weightKg($0, progress: progress) }.map { lightDay ? $0 - 5 : $0 }
                for (index, set) in planned.sets.enumerated() {
                    entry.sets?.append(WorkoutSet(order: index, reps: set.reps.map { weight == nil ? grown($0, progress: progress) : $0 },
                                                  seconds: set.seconds.map { grown($0, progress: progress) },
                                                  weightKg: weight,
                                                  exerciseID: planned.exerciseID, workoutStartedAt: startedAt))
                }
                order += 1
            }
        }
        workout.updateTotals()
        template.lastPerformedAt = max(template.lastPerformedAt ?? .distantPast, startedAt)
    }

    /// Barbell work grows by its own range over the ten weeks, in 2.5 kg steps, 5 kg less on a light day;
    /// bodyweight work has no weight.
    private static let weightRanges: [String: (from: Double, to: Double)] = [
        "barbell_back_squat": (60, 85), "barbell_bench_press": (45, 62.5), "barbell_row": (40, 55),
        "overhead_press": (27.5, 37.5), "romanian_deadlift": (50, 72.5),
    ]

    private static func weightKg(_ key: String, progress: Double) -> Double? {
        guard let range = weightRanges[key] else { return nil }
        return ((range.from + (range.to - range.from) * progress) / 2.5).rounded(.down) * 2.5
    }

    /// Bodyweight reps of 10 and more and plank time grow by about a third over the ten weeks.
    private static func grown(_ planned: Int, progress: Double) -> Int {
        planned >= 10 ? Int((Double(planned) * (1 + progress / 3)).rounded()) : planned
    }
}
#endif
