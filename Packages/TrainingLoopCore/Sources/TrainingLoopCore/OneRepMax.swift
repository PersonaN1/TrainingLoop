/// Estimated one-rep max (CONTEXT: Estimated 1RM, DESIGN V7). A reference value, never a record.
public enum OneRepMax {
    /// Sets with more reps aren't estimated: the formula drifts too far.
    public static let maxReps = 12

    /// Epley: weight × (1 + reps ÷ 30). A single rep is the lifted weight itself.
    /// Nil without a positive weight or with reps outside 1...12.
    public static func estimate(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, (1...maxReps).contains(reps) else { return nil }
        if reps == 1 { return weightKg }
        return weightKg * (1 + Double(reps) / 30)
    }
}
