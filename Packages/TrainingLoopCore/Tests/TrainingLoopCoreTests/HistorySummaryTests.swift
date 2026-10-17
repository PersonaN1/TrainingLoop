import Foundation
import Testing
@testable import TrainingLoopCore

struct HistorySummaryTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 18) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    // Friday, 16 October 2026.
    private var now: Date { date(10, 16, hour: 20) }

    @Test func monthTotalsAndWeeklyBars() {
        let workouts = [
            WorkoutFacts(startedAt: date(9, 29), durationSeconds: 3000, volumeKg: 1000, setsByGroup: [.back: 5]),
            WorkoutFacts(startedAt: date(10, 1), durationSeconds: 2400, volumeKg: 2000, setsByGroup: [.quads: 6]),
            WorkoutFacts(startedAt: date(10, 14), durationSeconds: 1800, volumeKg: 500,
                         setsByGroup: [.quads: 4, .chest: 3]),
        ]
        let summary = HistorySummary(workouts: workouts, period: .month, now: now, calendar: calendar)
        #expect(summary.workoutCount == 2)
        #expect(summary.totalSeconds == 4200)
        #expect(summary.volumeKg == 2500)
        // Weeks starting 28 Sep, 5 Oct, 12 Oct; the first one also counts its September workout.
        #expect(summary.buckets.map(\.volumeKg) == [3000, 0, 500])
        #expect(summary.setsByGroup.map(\.group) == [.quads, .chest])
        #expect(summary.setsByGroup.first?.sets == 10)
        #expect(summary.trainingDays.contains(calendar.startOfDay(for: date(9, 29))))
    }

    @Test func weekBarsAreDaysUpToToday() {
        #expect(SummaryPeriod.week.buckets(now: now, calendar: calendar).count == 5)
        #expect(SummaryPeriod.year.buckets(now: now, calendar: calendar).count == 10)
    }

    @Test func weekStreakSkipsAnEmptyCurrentWeek() {
        let dates = [date(10, 1), date(10, 7), date(9, 22)]
        // This week (12–18 Oct) has nothing yet: weeks of 5 Oct and 28 Sep count; 21 Sep's week too.
        #expect(HistorySummary.weekStreak(dates, now: now, calendar: calendar) == 3)
        #expect(HistorySummary.weekStreak(dates + [date(10, 13)], now: now, calendar: calendar) == 4)
        #expect(HistorySummary.weekStreak([date(9, 1)], now: now, calendar: calendar) == 0)
    }

    @Test func weekStreakAcrossAClockChangeAtMidnight() {
        // Chile moves its clocks forward at midnight: the week of 6 September 2026 starts at 01:00.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Santiago")!
        calendar.firstWeekday = 1
        let dates = [(8, 17), (8, 24), (8, 31), (9, 7)].map { month, day in
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
        #expect(HistorySummary.weekStreak(dates, now: now, calendar: calendar) == 4)
    }

    @Test func volumeNeedsWeightAndReps() {
        #expect(WorkoutVolume.of(weightKg: 60, reps: 8) == 480)
        #expect(WorkoutVolume.of(weightKg: nil, reps: 8) == 0)
        #expect(WorkoutVolume.of(weightKg: 20, reps: nil) == 0)
    }
}
