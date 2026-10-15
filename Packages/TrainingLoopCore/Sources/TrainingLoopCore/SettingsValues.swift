/// Weight unit for input and display (SPEC D15). Storage is always kilograms.
public enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kg, lb

    public static let kilogramsPerPound = 0.45359237

    public func fromKilograms(_ kg: Double) -> Double {
        self == .kg ? kg : kg / Self.kilogramsPerPound
    }

    public func toKilograms(_ value: Double) -> Double {
        self == .kg ? value : value * Self.kilogramsPerPound
    }
}

/// Signal sound sets, as in SetLoop (TECH T7); "Off" is `nil` where a set is optional.
public enum SoundSet: String, Codable, CaseIterable, Sendable {
    case glass, marimba, note
}
