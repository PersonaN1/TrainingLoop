import SwiftUI
import TrainingLoopCore

extension MuscleGroup {
    var title: String {
        switch self {
        case .chest: String(localized: "Chest")
        case .back: String(localized: "Back")
        case .traps: String(localized: "Traps")
        case .neck: String(localized: "Neck")
        case .shoulders: String(localized: "Shoulders")
        case .biceps: String(localized: "Biceps")
        case .triceps: String(localized: "Triceps")
        case .forearms: String(localized: "Forearms")
        case .abs: String(localized: "Abs")
        case .quads: String(localized: "Quads")
        case .hamstrings: String(localized: "Hamstrings")
        case .glutes: String(localized: "Glutes")
        case .calves: String(localized: "Calves")
        case .fullBody: String(localized: "group.fullBody", defaultValue: "Full Body")
        }
    }
}

extension Equipment {
    var title: String {
        switch self {
        case .bodyweight: String(localized: "Bodyweight")
        case .barbell: String(localized: "Barbell")
        case .dumbbell: String(localized: "Dumbbells")
        case .kettlebell: String(localized: "Kettlebell")
        case .machine: String(localized: "Machine")
        case .cable: String(localized: "Cable")
        case .band: String(localized: "Band")
        case .other: String(localized: "Other")
        }
    }
}

extension Measure {
    /// "Exercise type" in the form (DESIGN V10): users never see the word "measure".
    var title: String {
        switch self {
        case .reps: String(localized: "For Reps")
        case .time: String(localized: "For Time")
        }
    }
}

extension ExerciseSummary {
    /// "Barbell · 14 workouts · 80 kg × 6" or "Barbell · not done yet" (DESIGN V10).
    func line(equipment: Equipment, unit: WeightUnit) -> String {
        guard workoutCount > 0 else {
            return "\(equipment.title) · \(String(localized: "not done yet"))"
        }
        var parts = [equipment.title, String(localized: "\(workoutCount) workouts")]
        if let best { parts.append(best.text(equipment: equipment, unit: unit)) }
        return parts.joined(separator: " · ")
    }
}

extension ExerciseSummary.Best {
    func text(equipment: Equipment, unit: WeightUnit) -> String {
        switch self {
        case .weight(let kg, let reps):
            // On a bodyweight exercise the weight is added to the body: "+10 kg × 6".
            let sign = equipment == .bodyweight ? "+" : ""
            return sign + unit.weightText(kg) + " × \(reps)"
        case .reps(let reps):
            return reps.formatted()
        case .seconds(let seconds):
            return Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
        }
    }
}

extension WeightUnit {
    /// "62.5 kg" / "137.79 lb", up to two decimals.
    func weightText(_ kilograms: Double) -> String {
        let value = fromKilograms(kilograms).formatted(.number.precision(.fractionLength(0...2)))
        return switch self {
        case .kg: String(localized: "\(value) kg")
        case .lb: String(localized: "\(value) lb")
        }
    }
}

extension View {
    /// Keeps a name within `Limits.maxNameLength` characters while typing (SPEC D15).
    func nameLimit(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let capped = newValue.cappedName
            if capped != newValue { text.wrappedValue = capped }
        }
    }

    /// Keeps a note within `Limits.maxNoteLength` characters while typing (SPEC D15).
    func noteLimit(_ text: Binding<String>) -> some View {
        onChange(of: text.wrappedValue) { _, newValue in
            let capped = newValue.cappedNote
            if capped != newValue { text.wrappedValue = capped }
        }
    }

    /// Shown when adding a custom exercise is refused at the limit (SPEC D8).
    func exerciseLimitAlert(isPresented: Binding<Bool>) -> some View {
        alert("Exercise limit reached", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can keep up to \(Limits.maxCustomExercises) custom exercises. Delete unused ones to add a new one.")
        }
    }
}
