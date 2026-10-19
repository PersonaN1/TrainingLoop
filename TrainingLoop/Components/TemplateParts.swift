import SwiftData
import SwiftUI
import TrainingLoopCore

/// Text for template cards, the preview and the editor (DESIGN V5, V6).
enum TemplateFormat {
    /// "0:45", "1:30", "12:00".
    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))
    }

    /// "8 reps", "1 rep", "8–12 reps".
    static func reps(_ range: ClosedRange<Int>) -> String {
        guard range.lowerBound != range.upperBound else { return String(localized: "\(range.lowerBound) reps") }
        return String(localized: "\(rangeText(range)) reps")
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

    /// "3 exercises · 11 sets · 4,220 kg" under the record editor (D16).
    static func recordSummary(_ definition: TemplateDefinition, unit: WeightUnit) -> String {
        let volume = definition.exercises.flatMap(\.sets).reduce(0) { $0 + $1.volumeKg }
        return [String(localized: "\(definition.exercises.count) exercises"),
                String(localized: "\(definition.setCount) sets"),
                HistoryFormat.volume(volume, unit: unit)].joined(separator: " · ")
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

/// Two wheels: minutes and seconds for rest and timed sets (DESIGN V6), hours and minutes for
/// a workout's length (SPEC D19).
struct DurationSheet: View {
    enum Style {
        case minutesSeconds, hoursMinutes

        /// Seconds in one step of the left wheel.
        var large: Int { self == .minutesSeconds ? 60 : 3600 }
        var small: Int { large / 60 }
    }

    @Environment(\.dismiss) private var dismiss
    let title: String
    let range: ClosedRange<Int>
    let style: Style
    let save: (Int) -> Void
    @State private var large: Int
    @State private var small: Int

    init(title: String, seconds: Int, range: ClosedRange<Int>, style: Style = .minutesSeconds,
         save: @escaping (Int) -> Void) {
        self.title = title
        self.range = range
        self.style = style
        self.save = save
        _large = State(initialValue: seconds / style.large)
        _small = State(initialValue: seconds % style.large / style.small)
    }

    private var total: Int { large * style.large + small * style.small }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                switch style {
                case .minutesSeconds:
                    Picker("Minutes", selection: $large) {
                        ForEach(0...(range.upperBound / 60), id: \.self) { Text(String(localized: "\($0) min")).tag($0) }
                    }
                    Picker("Seconds", selection: $small) {
                        ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) s")).tag($0) }
                    }
                case .hoursMinutes:
                    Picker("Hours", selection: $large) {
                        ForEach(0...(range.upperBound / 3600), id: \.self) { Text(String(localized: "\($0) h")).tag($0) }
                    }
                    Picker("Minutes", selection: $small) {
                        ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) min")).tag($0) }
                    }
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
/// An empty weight means "use the previous time's weight" (D4). A done set by sides has both sides (D23).
struct SetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    let number: Int
    let measure: Measure
    let weighted: Bool
    let lastWeightKnown: Bool
    /// A set of a finished workout: an empty weight is no weight, not last time's.
    let isDone: Bool
    /// Left and right have their own values.
    let bySide: Bool
    let canDelete: Bool
    /// nil deletes the set.
    let save: (PlannedSet?) -> Void
    @State private var left: SideInput
    @State private var right: SideInput
    @FocusState private var weightFocused: Bool

    /// What the controls of one side hold.
    private struct SideInput {
        var reps: Int
        var minutes: Int
        var seconds: Int
        var weightText: String

        init(reps: Int?, seconds: Int?, weightKg: Double?, unit: WeightUnit) {
            self.reps = reps ?? 10
            let time = seconds ?? 45
            minutes = time / 60
            self.seconds = time % 60
            // No grouping: "1,102.5" would not read back as a number.
            weightText = weightKg.map {
                WeightInput.displayValue($0, unit: unit).formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
            } ?? ""
        }

        var timeTotal: Int { minutes * 60 + seconds }

        func isValid(_ measure: Measure) -> Bool {
            measure == .reps ? SetRanges.reps.contains(reps) : SetRanges.seconds.contains(timeTotal)
        }
    }

    init(number: Int, set: PlannedSet, measure: Measure, weighted: Bool, lastWeightKnown: Bool, isDone: Bool = false,
         bySide: Bool = false, unit: WeightUnit,
         canDelete: Bool, save: @escaping (PlannedSet?) -> Void) {
        self.number = number
        self.measure = measure
        self.weighted = weighted
        self.lastWeightKnown = lastWeightKnown
        self.isDone = isDone
        self.bySide = bySide
        self.canDelete = canDelete
        self.save = save
        _left = State(initialValue: SideInput(reps: set.reps, seconds: set.seconds, weightKg: set.weightKg, unit: unit))
        // A set not split yet starts both sides alike.
        let right = set.sides.last ?? set
        _right = State(initialValue: SideInput(reps: right.reps, seconds: right.seconds, weightKg: right.weightKg,
                                               unit: unit))
    }

    private var isValid: Bool {
        left.isValid(measure) && (!bySide || right.isValid(measure))
    }

    var body: some View {
        NavigationStack {
            Form {
                if bySide {
                    controls($left, header: Text("Left"))
                    controls($right, header: Text("Right"))
                } else {
                    controls($left, header: nil)
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
            .keyboardDismissButton()
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
        .presentationDetents(bySide ? [.large] : [.medium, .large])
    }

    @ViewBuilder
    private func controls(_ input: Binding<SideInput>, header: Text?) -> some View {
        Section {
            switch measure {
            case .reps:
                Stepper(value: input.reps, in: SetRanges.reps) {
                    LabeledContent("Reps", value: input.wrappedValue.reps.formatted())
                        .monospacedDigit()
                }
            case .time:
                HStack(spacing: 0) {
                    Picker("Minutes", selection: input.minutes) {
                        ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) min")).tag($0) }
                    }
                    Picker("Seconds", selection: input.seconds) {
                        ForEach(0..<60, id: \.self) { Text(String(localized: "\($0) s")).tag($0) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .monospacedDigit()
            }
            if weighted {
                HStack {
                    Text("Weight")
                    TextField("Weight", text: input.weightText,
                              prompt: lastWeightKnown ? Text("last time's weight") : Text(verbatim: ""))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .focused($weightFocused)
                    Text(settings.weightUnit == .kg ? "kg" : "lb").foregroundStyle(.secondary)
                }
            }
        } header: {
            if let header { header }
        } footer: {
            if weighted && !isDone && !bySide {
                Text("Leave empty to use the weight from the previous time.")
            }
        }
    }

    private var result: PlannedSet {
        var set = values(left)
        if bySide {
            let side = values(right)
            set.right = .init(reps: side.reps, seconds: side.seconds, weightKg: side.weightKg)
        }
        return set
    }

    private func values(_ input: SideInput) -> PlannedSet {
        PlannedSet(reps: measure == .reps ? input.reps : nil,
                   seconds: measure == .time ? input.timeTotal : nil,
                   weightKg: weighted ? WeightInput.kilograms(from: input.weightText, unit: settings.weightUnit) : nil)
    }
}
