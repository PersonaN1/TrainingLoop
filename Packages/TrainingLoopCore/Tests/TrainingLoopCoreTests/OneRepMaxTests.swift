import Testing
@testable import TrainingLoopCore

struct OneRepMaxTests {
    @Test func epleyFormula() throws {
        // DESIGN V7 example: 75 kg × 5 → 87.5 kg.
        let estimate = try #require(OneRepMax.estimate(weightKg: 75, reps: 5))
        #expect(abs(estimate - 87.5) < 0.0001)
    }

    @Test func singleRepIsTheLiftedWeight() {
        #expect(OneRepMax.estimate(weightKg: 100, reps: 1) == 100)
    }

    @Test func twelveRepsIsTheLimit() throws {
        let estimate = try #require(OneRepMax.estimate(weightKg: 60, reps: 12))
        #expect(abs(estimate - 84) < 0.0001)
        #expect(OneRepMax.estimate(weightKg: 60, reps: 13) == nil)
    }

    @Test(arguments: [(0.0, 5), (-5.0, 5), (50.0, 0), (50.0, -1)])
    func noEstimateWithoutWeightOrReps(weightKg: Double, reps: Int) {
        #expect(OneRepMax.estimate(weightKg: weightKg, reps: reps) == nil)
    }
}
