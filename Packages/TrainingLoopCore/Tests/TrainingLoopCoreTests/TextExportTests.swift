import Foundation
import Testing
@testable import TrainingLoopCore

struct TextExportTests {
    private let squat = UUID()
    private let pullUp = UUID()
    private let deadlift = UUID()
    private let plank = UUID()

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 18, minute: Int = 5, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func export(_ language: String, unit: WeightUnit = .kg) -> TextExport {
        let names: [UUID: (en: String, ru: String, adds: Bool)] = [
            squat: ("Barbell Squat", "Присед со штангой", false),
            pullUp: ("Pull-up", "Подтягивания", true),
            deadlift: ("Romanian Deadlift", "Румынская тяга", false),
            plank: ("Plank", "Планка", true),
        ]
        return TextExport(unit: unit, locale: Locale(identifier: language == "ru" ? "ru_RU" : "en_US"),
                          calendar: calendar) { id in
            let entry = names[id]!
            return .init(name: language == "ru" ? entry.ru : entry.en, addsWeight: entry.adds)
        }
    }

    /// Superset squat ↔ pull-ups ×4, then a deadlift with rising weights and a plank.
    private var template: TemplateDefinition {
        TemplateDefinition(items: [
            .superset(TemplateSuperset(exercises: [
                TemplateExercise(exerciseID: squat, sets: Array(repeating: PlannedSet(reps: 8, weightKg: 60), count: 4),
                                 restSeconds: 0),
                TemplateExercise(exerciseID: pullUp, sets: Array(repeating: PlannedSet(reps: 8), count: 4),
                                 restSeconds: 0),
            ], restWithinSeconds: 30, restAfterSeconds: 90)),
            .exercise(TemplateExercise(exerciseID: deadlift, sets: [
                PlannedSet(reps: 10, weightKg: 60), PlannedSet(reps: 8, weightKg: 70), PlannedSet(reps: 6, weightKg: 80),
            ], restSeconds: 90)),
            .exercise(TemplateExercise(exerciseID: plank, sets: Array(repeating: PlannedSet(seconds: 45), count: 3),
                                       restSeconds: 60)),
        ])
    }

    private var workout: TextExport.Workout {
        TextExport.Workout(name: "Legs", startedAt: date(10, 14), durationSeconds: 52 * 60 + 30,
                           note: "  Knee fine\n", definition: TemplateDefinition(items: [
            .superset(TemplateSuperset(exercises: [
                TemplateExercise(exerciseID: squat, sets: [
                    PlannedSet(reps: 10, weightKg: 60), PlannedSet(reps: 8, weightKg: 62.5),
                ], restSeconds: 0),
                TemplateExercise(exerciseID: pullUp, sets: [PlannedSet(reps: 8), PlannedSet(reps: 6, weightKg: 5)],
                                 restSeconds: 0),
            ], restWithinSeconds: 30, restAfterSeconds: 90)),
            .exercise(TemplateExercise(exerciseID: plank, sets: [PlannedSet(seconds: 45), PlannedSet(seconds: 60)],
                                       restSeconds: 60)),
        ]))
    }

    @Test func templateInEnglish() {
        let text = export("en").template(name: "Legs + Pull-ups", definition: template)
        #expect(text == """
            Legs + Pull-ups
            4 exercises · 14 sets · ~\(template.estimatedMinutes!) min

            Superset · 4 rounds · rest 0:30 / 1:30
            – Barbell Squat: 4 × 8 · 60 kg
            – Pull-up: 4 × 8

            Romanian Deadlift: 60 kg × 10, 70 kg × 8, 80 kg × 6 · rest 1:30

            Plank: 3 × 0:45 · rest 1:00
            """)
    }

    @Test func templateInRussianWithPlurals() {
        let text = export("ru").template(name: "Ноги", definition: template)
        #expect(text.hasPrefix("Ноги\n4 упражнения · 14 подходов · ~"))
        #expect(text.contains("Суперсет · 4 круга · отдых 0:30 / 1:30\n– Присед со штангой: 4 × 8 · 60 кг"))
        #expect(text.contains("Планка: 3 × 0:45 · отдых 1:00"))
    }

    @Test func templateSetsWithoutValues() {
        let definition = TemplateDefinition(items: [
            .exercise(TemplateExercise(exerciseID: squat, sets: Array(repeating: PlannedSet(), count: 3), restSeconds: 0)),
            .exercise(TemplateExercise(exerciseID: deadlift, sets: Array(repeating: PlannedSet(weightKg: 80), count: 2),
                                       restSeconds: 0)),
            .exercise(TemplateExercise(exerciseID: plank, sets: [], restSeconds: 0)),
        ])
        let text = export("ru").template(name: "T", definition: definition)
        #expect(text.contains("Присед со штангой: 3 подхода\n"))
        #expect(text.contains("Румынская тяга: 2 подхода · 80 кг\n"))
        #expect(text.hasSuffix("Планка: —"))
    }

    @Test func workoutListsEverySet() {
        let text = export("en").workout(workout)
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0] == "Legs")
        #expect(lines[1].hasPrefix("Wed, October 14, 2026 · "))
        #expect(lines[1].hasSuffix(" · 52 min"))
        #expect(text.contains("""

            Superset
            – Barbell Squat: 60 kg × 10, 62.5 kg × 8
            – Pull-up: 8, +5 kg × 6

            Plank: 0:45, 1:00

            Total: 3 exercises · 6 sets · 1,130 kg
            Note: Knee fine
            """))
        #expect(text.hasSuffix("Note: Knee fine"))
    }

    @Test func workoutInRussianPoundsWithoutNote() {
        var workout = workout
        workout.note = " "
        let text = export("ru", unit: .lb).workout(workout)
        #expect(text.hasPrefix("Legs\nСр, 14 октября 2026"))
        #expect(text.contains("– Присед со штангой: 132,28 фнт × 10, 137,79 фнт × 8"))
        #expect(text.contains("– Подтягивания: 8, +11,02 фнт × 6"))
        // Russian groups digits with a no-break space.
        #expect(text.hasSuffix("Итого: 3 упражнения · 6 подходов · 2\u{00A0}491 фнт"))
        #expect(!text.contains("Заметка"))
    }

    /// A set by sides lists both, and its volume adds both (D23).
    @Test func workoutSetBySides() {
        let sided = TextExport.Workout(name: "Arms", startedAt: date(10, 1), durationSeconds: 600, note: "",
                                       definition: TemplateDefinition(items: [
            .exercise(TemplateExercise(exerciseID: deadlift, sets: [
                PlannedSet(reps: 10, weightKg: 14, right: .init(reps: 9, weightKg: 12)),
            ], restSeconds: 0)),
        ]))
        #expect(export("en").workout(sided).hasSuffix(
            "Romanian Deadlift: L 14 kg × 10 / R 12 kg × 9\n\nTotal: 1 exercise · 1 set · 248 kg"))
        #expect(export("ru").workout(sided).contains("Румынская тяга: Л 14 кг × 10 / П 12 кг × 9"))
    }

    @Test func workoutWithoutWeightLeavesVolumeOut() {
        let bodyweight = TextExport.Workout(name: "Home", startedAt: date(10, 1), durationSeconds: 600, note: "",
                                            definition: TemplateDefinition(items: [
            .exercise(TemplateExercise(exerciseID: pullUp, sets: [PlannedSet(reps: 1)], restSeconds: 0)),
        ]))
        #expect(export("en").workout(bodyweight).hasSuffix("Pull-up: 1\n\nTotal: 1 exercise · 1 set"))
    }

    @Test func periodOldestFirstWithTotals() {
        var older = workout
        older.name = "First"
        older.startedAt = date(10, 2)
        older.durationSeconds = 3600
        let text = export("en").period([workout, older], interval: DateInterval(start: date(10, 1, hour: 0, minute: 0),
                                                                               end: date(11, 1, hour: 0, minute: 0)))
        let lines = text.components(separatedBy: "\n")
        #expect(lines[0].hasPrefix("TrainingLoop · October 1"))
        #expect(lines[0].hasSuffix("31, 2026"))
        #expect(lines[1] == "2 workouts · 1 hr, 52 min · 2,260 kg")
        let first = text.range(of: "———\nFirst\n")
        let second = text.range(of: "———\nLegs\n")
        #expect(first != nil && second != nil && first!.lowerBound < second!.lowerBound)
        // Within one year the workouts' dates skip it; the header has it.
        #expect(text.contains("\nFri, October 2 · "))
    }

    @Test func periodOfAllSpanningYears() {
        var older = workout
        older.startedAt = date(12, 30, year: 2025)
        let text = export("ru").period([workout, older], interval: nil)
        #expect(text.components(separatedBy: "\n")[1].hasPrefix("2 тренировки · "))
        #expect(text.contains("Вт, 30 декабря 2025"))
        #expect(text.contains("Ср, 14 октября 2026"))
    }

    @Test func emptyPeriod() {
        #expect(export("ru").period([], interval: nil) == "TrainingLoop\n0 тренировок · 0 мин")
    }
}

