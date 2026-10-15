import Testing
@testable import TrainingLoopCore

struct WeightUnitTests {
    @Test func kilogramsPassThrough() {
        #expect(WeightUnit.kg.fromKilograms(62.5) == 62.5)
        #expect(WeightUnit.kg.toKilograms(62.5) == 62.5)
    }

    @Test func poundsRoundTripWithoutLoss() {
        let pounds = WeightUnit.lb.fromKilograms(100)
        #expect(abs(pounds - 220.462) < 0.001)
        #expect(abs(WeightUnit.lb.toKilograms(pounds) - 100) < 1e-9)
    }
}
