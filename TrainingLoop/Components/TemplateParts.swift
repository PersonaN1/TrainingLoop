import SwiftData
import SwiftUI
import TrainingLoopCore

/// Text for template cards, the preview and the editor (DESIGN V5, V6).
enum TemplateFormat {
    /// "0:45", "1:30", "12:00".
    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    static func reps(_ range: ClosedRange<Int>) -> String {
        String(localized: "\(rangeText(range)) reps")
    }

    static func rangeText(_ range: ClosedRange<Int>) -> String {
        range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
    }

    /// "3 exercises · 11 sets · ~25 min".
    static func summary(_ definition: TemplateDefinition) -> String {
        var parts = [String(localized: "\(definition.exercises.count) exercises"),
                     String(localized: "\(definition.setCount) sets")]
        if let minutes = definition.estimatedMinutes { parts.append(String(localized: "~\(minutes) min")) }
        return parts.joined(separator: " · ")
    }

    /// "~60 min · 3 days ago" or "~20 min · Not done yet" under a card.
    static func footer(_ definition: TemplateDefinition, lastPerformedAt: Date?) -> String {
        var parts: [String] = []
        if let minutes = definition.estimatedMinutes { parts.append(String(localized: "~\(minutes) min")) }
        if let lastPerformedAt {
            parts.append(lastPerformedAt.formatted(.relative(presentation: .named)))
        } else {
            parts.append(String(localized: "template.notDone", defaultValue: "Not done yet"))
        }
        return parts.joined(separator: " · ")
    }
}

extension SetsSummary {
    /// "4×8", "3×10–12", "3×45 s"; just "3" when no set has a value.
    var cardText: String {
        switch value {
        case .reps(let range): "\(count)×\(TemplateFormat.rangeText(range))"
        case .seconds(let range):
            "\(count)×" + (range.lowerBound == range.upperBound
                ? String(localized: "\(range.lowerBound) s")
                : String(localized: "\(TemplateFormat.rangeText(range)) s"))
        case nil: "\(count)"
        }
    }

    /// "4 sets · 6–8 reps · 60 kg" in the preview.
    func previewText(_ sets: [PlannedSet], unit: WeightUnit, equipment: Equipment?) -> String {
        var parts = [String(localized: "\(count) sets")]
        switch value {
        case .reps(let range): parts.append(TemplateFormat.reps(range))
        case .seconds(let range):
            parts.append(range.lowerBound == range.upperBound
                ? TemplateFormat.duration(range.lowerBound)
                : "\(TemplateFormat.duration(range.lowerBound))–\(TemplateFormat.duration(range.upperBound))")
        case nil: break
        }
        let weights = sets.compactMap(\.weightKg)
        if let low = weights.min(), let high = weights.max() {
            let sign = equipment == .bodyweight ? "+" : ""
            parts.append(low == high
                ? sign + unit.weightText(low)
                : sign + "\(unit.weightText(low))–\(unit.weightText(high))")
        }
        return parts.joined(separator: " · ")
    }
}

/// All exercises by ID, archived and hidden included: a template may still use them.
struct ExerciseLookup {
    private let byID: [UUID: Exercise]

    init(_ exercises: [Exercise]) {
        byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    subscript(id: UUID) -> Exercise? { byID[id] }

    func name(_ id: UUID) -> String {
        byID[id]?.name ?? String(localized: "Unknown Exercise")
    }
}

/// The sea-blue stripe on the left of a superset's rows (DESIGN V4, V5).
struct SupersetRowBackground: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.accentColor.frame(width: 4)
            Color(.secondarySystemGroupedBackground)
        }
    }
}

/// Minutes and seconds wheels: rest and timed sets (DESIGN V6).
struct DurationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let range: ClosedRange<Int>
    let save: (Int) -> Void
    @State private var minutes: Int
    @State private var seconds: Int

    init(title: String, seconds: Int, range: ClosedRange<Int>, save: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.save = save
        _minutes = State(initialValue: seconds / 60)
        _seconds = State(initialValue: seconds % 60)
    }

    private var total: Int { minutes * 60 + seconds }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Minutes", selection: $minutes) {
                    ForEach(0...(range.upperBound / 60), id: \.self) { Text(String(localized: "\($0) min")).tag($0) }
                }
                Picker("Seconds", selection: $seconds) {
                    ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) s")).tag($0) }
                }
            }
            .pickerStyle(.wheel)
            .monospacedDigit()
            .padding(.horizontal)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save(min(max(total, range.lowerBound), range.upperBound))
                        dismiss()
                    }
                    .disabled(!range.contains(total))
                }
            }
        }
        .presentationDetents([.height(320)])
    }
}

/// One planned set (SPEC D4, D15): reps or time, and weight when the exercise is weighted.
/// An empty weight means "use the previous time's weight" (D4).
struct SetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let number: Int
    let measure: Measure
    let weighted: Bool
    let lastWeightKnown: Bool
    let canDelete: Bool
    /// nil deletes the set.
    let save: (PlannedSet?) -> Void
    @State private var reps: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var weightText: String
    @FocusState private var weightFocused: Bool

    init(number: Int, set: PlannedSet, measure: Measure, weighted: Bool, lastWeightKnown: Bool, unit: WeightUnit,
         canDelete: Bool, save: @escaping (PlannedSet?) -> Void) {
        self.number = number
        self.measure = measure
        self.weighted = weighted
        self.lastWeightKnown = lastWeightKnown
        self.canDelete = canDelete
        self.save = save
        _reps = State(initialValue: set.reps ?? 10)
        let time = set.seconds ?? 45
        _minutes = State(initialValue: time / 60)
        _seconds = State(initialValue: time % 60)
        _weightText = State(initialValue: set.weightKg.map {
            WeightInput.displayValue($0, unit: unit).formatted(.number.precision(.fractionLength(0...2)))
        } ?? "")
    }

    private var timeTotal: Int { minutes * 60 + seconds }

    private var isValid: Bool {
        measure == .reps ? SetRanges.reps.contains(reps) : SetRanges.seconds.contains(timeTotal)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch measure {
                case .reps:
                    Stepper(value: $reps, in: SetRanges.reps) {
                        LabeledContent("Reps", value: reps.formatted())
                            .monospacedDigit()
                    }
                case .time:
                    HStack(spacing: 0) {
                        Picker("Minutes", selection: $minutes) {
                            ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) min")).tag($0) }
                        }
                        Picker("Seconds", selection: $seconds) {
                            ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) s")).tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                    .monospacedDigit()
                }
                if weighted {
                    Section {
                        HStack {
                            Text("Weight")
                            TextField("Weight", text: $weightText,
                                      prompt: lastWeightKnown ? Text("last time's weight") : Text(verbatim: ""))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($weightFocused)
                            Text(settings.weightUnit == .kg ? "kg" : "lb").foregroundStyle(.secondary)
                        }
                    } footer: {
                        Text("Leave empty to use the weight from the previous time.")
                    }
                }
                if canDelete {
                    Section {
                        Button("Delete Set", role: .destructive) {
                            save(nil)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "Set \(number)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        save(result)
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var result: PlannedSet {
        PlannedSet(reps: measure == .reps ? reps : nil,
                   seconds: measure == .time ? timeTotal : nil,
                   weightKg: weighted ? WeightInput.kilograms(from: weightText, unit: settings.weightUnit) : nil)
    }
}
