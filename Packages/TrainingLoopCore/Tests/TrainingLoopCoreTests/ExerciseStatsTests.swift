import Foundation
import Testing
@testable import TrainingLoopCore

struct ExerciseStatsTests {
    private func day(_ n: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(n) * 86_400) }
    private func set(_ kg: Double?, _ reps: Int) -> PlannedSet { PlannedSet(reps: reps, weightKg: kg) }

    private var bench: ExerciseStats {
        ExerciseStats(sessions: [
            // Out of order on purpose: sessions are sorted by date.
            .init(date: day(3), sets: [set(80, 3), set(70, 6)]),
            .init(date: day(1), sets: [set(60, 10), set(70, 5)]),
            .init(date: day(2), sets: [set(70, 5), set(70, 5)]),
        ])
    }

    @Test func pointsFollowTheDatesAndMarkRecords() {
        let weight = bench.points(.bestWeight)
        #expect(weight.map(\.value) == [70, 70, 80])
        // Only the peak is the record.
        #expect(weight.map(\.isRecord) == [false, false, true])

        let volume = bench.points(.volume)
        #expect(volume.map(\.value) == [950, 700, 660])
        #expect(volume.map(\.isRecord) == [true, false, false])
    }

    @Test func onlyThePeakIsARecordAfterADip() {
        // Progress, peak, dip, progress again: one record, the earliest of equal peaks.
        let stats = ExerciseStats(sessions: [60, 70, 80, 65, 75, 80].enumerated().map { day, kg in
            .init(date: self.day(day), sets: [set(kg, 5)])
        })
        #expect(stats.points(.bestWeight).map(\.isRecord) == [false, false, true, false, false, false])
    }

    @Test func tilesComeFromRealSets() {
        let stats = bench
        #expect(stats.bestWeight == .init(value: 80, set: set(80, 3), date: day(3)))
        // Epley: 80 × 3 → 88 beats 70 × 6 → 84 and 60 × 10 → 80.
        #expect(stats.estimatedMax?.value == 80 * (1 + 3.0 / 30))
        #expect(stats.bestVolume == .init(value: 950, set: nil, date: day(1)))
        #expect(stats.maxReps?.value == 10)
        #expect(stats.maxSeconds == nil)
        #expect(stats.workoutCount == 3)
    }

    @Test func bestWeightForRepsCountsSetsWithAtLeastThatManyReps() {
        let best = bench.bestWeightForReps.map { ($0.reps, $0.best.value, $0.best.date) }
        #expect(best.map(\.0) == [1, 3, 5, 8, 10])
        #expect(best.map(\.1) == [80, 80, 70, 60, 60])
        // Of equal weights the earliest set holds it.
        #expect(best[2].2 == day(1))
    }

    @Test func equalWeightsGoToMoreReps() {
        let stats = ExerciseStats(sessions: [
            .init(date: day(1), sets: [set(100, 3)]),
            .init(date: day(2), sets: [set(100, 5)]),
        ])
        #expect(stats.bestWeight?.set == set(100, 5))
    }

    @Test func metricsFollowTheExerciseKind() {
        #expect(ExerciseStats.Metric.available(measure: .reps, weighted: true) == [.bestWeight, .volume])
        #expect(ExerciseStats.Metric.available(measure: .reps, weighted: false) == [.maxReps, .totalReps])
        #expect(ExerciseStats.Metric.available(measure: .time, weighted: false) == [.maxSeconds])
    }

    @Test func withoutWeightRepsAndTotals() {
        let stats = ExerciseStats(sessions: [
            .init(date: day(1), sets: [set(nil, 15), set(nil, 12)]),
            .init(date: day(2), sets: [set(nil, 18), set(nil, 10)]),
        ])
        #expect(stats.points(.maxReps).map(\.value) == [15, 18])
        #expect(stats.points(.maxReps).map(\.isRecord) == [false, true])
        #expect(stats.points(.totalReps).map(\.value) == [27, 28])
        #expect(stats.points(.bestWeight).isEmpty)
        #expect(stats.bestWeight == nil)
        #expect(stats.estimatedMax == nil)
        #expect(!stats.hasWeight)
        #expect(bench.hasWeight)
    }

    @Test func timedSets() {
        let stats = ExerciseStats(sessions: [
            .init(date: day(1), sets: [PlannedSet(seconds: 45), PlannedSet(seconds: 60)]),
            .init(date: day(2), sets: [PlannedSet(seconds: 75)]),
        ])
        #expect(stats.points(.maxSeconds).map(\.value) == [60, 75])
        #expect(stats.points(.maxSeconds).map(\.isRecord) == [false, true])
        #expect(stats.maxSeconds == .init(value: 75, set: PlannedSet(seconds: 75), date: day(2)))
    }
}
