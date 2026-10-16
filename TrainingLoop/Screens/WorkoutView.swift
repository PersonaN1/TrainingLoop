import SwiftData
import SwiftUI
import TrainingLoopCore

/// The workout in progress: every exercise in one list, the next set highlighted, the rest at the bottom
/// (SPEC D5–D7; DESIGN V3, V4).
struct WorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]
    /// Finished exercises the user opened again.
    @State private var expanded = Set<UUID>()
    @State private var picker: PickerTarget?
    @State private var confirmingFinish = false

    private enum PickerTarget: Identifiable {
        case add
        case replace(UUID)

        var id: String {
            switch self {
            case .add: "add"
            case .replace(let id): id.uuidString
            }
        }
    }

    var body: some View {
        @Bindable var workouts = workouts
        NavigationStack {
            if let workout = workouts.workout {
                list(workout)
                    .navigationTitle(workout.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(workout) }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let rest = workouts.rest {
                            RestPanel(rest: rest, next: nextText(workout))
                        }
                    }
                    .sheet(item: $picker) { target in
                        switch target {
                        case .add:
                            ExercisePickerView(mode: .add) { picked in
                                workouts.addExercises(picked.map(\.id), context: context)
                            }
                        case .replace(let id):
                            ExercisePickerView(mode: .replace) { picked in
                                if let exercise = picked.first {
                                    workouts.replaceExercise(id, with: exercise.id, context: context)
                                }
                            }
                        }
                    }
                    .sheet(isPresented: Binding(get: { workouts.finishingAt != nil },
                                                set: { if !$0 { workouts.finishingAt = nil } })) {
                        WorkoutSummaryView()
                    }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ workout: ActiveWorkout) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button("Collapse", systemImage: "chevron.down") { workouts.isPresented = false }
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(workout.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(workout.startedAt, style: .timer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Finish") {
                if workout.doneSetCount == 0 { confirmingFinish = true } else { workouts.finish() }
            }
            .confirmationDialog("No sets are marked", isPresented: $confirmingFinish, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) { workouts.discard() }
            } message: {
                Text("There is nothing to save.")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
    }

    private func list(_ workout: ActiveWorkout) -> some View {
        let lookup = ExerciseLookup(allExercises)
        let next = workout.nextPosition.map { workout[$0].id }
        return ScrollViewReader { proxy in
            List {
                ForEach(Array(workout.items.enumerated()), id: \.element.id) { itemIndex, item in
                    switch item {
                    case .exercise(let exercise):
                        Section {
                            exerciseRows(exercise, lookup: lookup, next: next)
                        }
                    case .superset(let superset):
                        Section {
                            ForEach(superset.exercises) { exerciseRows($0, lookup: lookup, next: next, inSuperset: true) }
                        } header: {
                            Text(supersetTitle(superset, workout: workout, itemIndex: itemIndex))
                        }
                        .listRowBackground(SupersetRowBackground())
                    }
                }
                Section {
                    Button("Add Exercises", systemImage: "plus") { picker = .add }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if workout.items.isEmpty {
                    ContentUnavailableView {
                        Label("No Exercises", systemImage: "dumbbell")
                    } description: {
                        Text("Add exercises to start.")
                    } actions: {
                        Button("Add Exercises") { picker = .add }
                    }
                }
            }
            // After a tick the list follows the highlight (DESIGN V4).
            .onChange(of: next) { _, id in
                guard let id else { return }
                withAnimation { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    /// "Superset · round 2 of 4": the round of the next set while the superset goes on.
    private func supersetTitle(_ superset: ActiveWorkout.Superset, workout: ActiveWorkout, itemIndex: Int) -> String {
        let rounds = superset.exercises.map(\.sets.count).max() ?? 0
        let round: Int
        if let next = workout.nextPosition, next.item == itemIndex {
            round = next.set + 1
        } else if superset.exercises.allSatisfy({ $0.sets.allSatisfy(\.isDone) }) {
            round = rounds
        } else {
            round = 1
        }
        return String(localized: "Superset · round \(round) of \(rounds)")
    }

    @ViewBuilder
    private func exerciseRows(_ exercise: ActiveWorkout.Exercise, lookup: ExerciseLookup, next: UUID?,
                              inSuperset: Bool = false) -> some View {
        let stored = lookup[exercise.exerciseID]
        let measure = stored?.measure ?? .reps
        let weighted = stored?.weighted ?? false
        let finished = !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isDone)
        if finished && !expanded.contains(exercise.id) {
            // "Squat ✓ 4 sets"; a tap opens it again (DESIGN V3).
            Button {
                withAnimation { _ = expanded.insert(exercise.id) }
            } label: {
                HStack {
                    Text(lookup.name(exercise.exerciseID)).font(.headline)
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    Spacer()
                    Text("\(exercise.sets.count) sets").foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
        } else {
            HStack {
                Text(lookup.name(exercise.exerciseID)).font(.headline)
                Spacer()
                Menu {
                    Button("Add Set", systemImage: "plus") { workouts.change { $0.addSet(to: exercise.id) } }
                    Button("Replace", systemImage: "arrow.left.arrow.right") { picker = .replace(exercise.id) }
                    if finished {
                        Button("Collapse", systemImage: "chevron.up") {
                            withAnimation { _ = expanded.remove(exercise.id) }
                        }
                    }
                    Button("Remove Exercise", systemImage: "trash", role: .destructive) {
                        workouts.change { $0.removeExercise(exercise.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .accessibilityLabel("More")
            }
            SetColumnsHeader(measure: measure, weighted: weighted, unit: settings.weightUnit)
            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                SetRowView(number: index + 1, row: set, measure: measure, weighted: weighted,
                           unit: settings.weightUnit, isNext: set.id == next, inSuperset: inSuperset)
                    .id(set.id)
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            workouts.change { $0.removeSet(set.id) }
                        }
                    }
            }
            Button("Add Set", systemImage: "plus") { workouts.change { $0.addSet(to: exercise.id) } }
                .font(.subheadline)
        }
    }

    /// "Next: Squat, set 3".
    private func nextText(_ workout: ActiveWorkout) -> String? {
        guard let position = workout.nextPosition else { return nil }
        let name = ExerciseLookup(allExercises).name(workout.exercise(at: position).exerciseID)
        return String(localized: "Next: \(name), set \(position.set + 1)")
    }
}

/// Column captions over the set rows (D7).
private struct SetColumnsHeader: View {
    let measure: Measure
    let weighted: Bool
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 8) {
            Text("#", comment: "Set number column").frame(width: 28, alignment: .leading)
            Text("Last Time").frame(maxWidth: .infinity, alignment: .leading)
            if weighted {
                Text(unit == .kg ? "kg" : "lb").frame(width: SetRowView.fieldWidth)
            }
            Text(measure == .reps ? "Reps" : "Sec").frame(width: SetRowView.fieldWidth)
            Color.clear.frame(width: SetRowView.checkWidth, height: 1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
    }
}

/// № · last time · weight · reps or seconds · tick. Suggested values show in grey and a tick takes them (D7).
private struct SetRowView: View {
    @Environment(WorkoutController.self) private var workouts
    static let fieldWidth: CGFloat = 64
    static let checkWidth: CGFloat = 36

    let number: Int
    let row: ActiveWorkout.SetRow
    let measure: Measure
    let weighted: Bool
    let unit: WeightUnit
    let isNext: Bool
    let inSuperset: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(number.formatted())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            Text(lastTime)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if weighted {
                TextField("Weight", value: weightBinding, format: .number.precision(.fractionLength(0...2)),
                          prompt: Text(row.suggested.weightKg.map { format(weight: $0) } ?? "–"))
                    .keyboardType(.decimalPad)
                    .field(width: Self.fieldWidth)
            }
            switch measure {
            case .reps:
                TextField("Reps", value: intBinding(\.reps), format: .number,
                          prompt: Text(row.suggested.reps.map { $0.formatted() } ?? "–"))
                    .keyboardType(.numberPad)
                    .field(width: Self.fieldWidth)
            case .time:
                TextField("Seconds", value: intBinding(\.seconds), format: .number,
                          prompt: Text(row.suggested.seconds.map { $0.formatted() } ?? "–"))
                    .keyboardType(.numberPad)
                    .field(width: Self.fieldWidth)
            }
            Button {
                workouts.toggle(row.id)
            } label: {
                Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(row.isDone ? Color.accentColor : Color.secondary)
                    .frame(width: Self.checkWidth, height: 36)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .disabled(!canTick)
            .accessibilityLabel(row.isDone ? "Done" : "Mark Done")
        }
        .monospacedDigit()
        .listRowBackground(ZStack {
            if inSuperset { SupersetRowBackground() } else { Color(.secondarySystemGroupedBackground) }
            if isNext { Color.accentColor.opacity(0.12) }
        })
    }

    /// Without reps or time there is nothing to record.
    private var canTick: Bool {
        row.isDone || (measure == .reps ? row.value.reps != nil : row.value.seconds != nil)
    }

    /// "60 × 8", "× 8", "45 s" or "–".
    private var lastTime: String {
        guard let previous = row.previous else { return "–" }
        let amount = previous.reps.map { "\($0)" } ?? previous.seconds.map { String(localized: "\($0) s") } ?? ""
        if let weight = previous.weightKg, weighted { return "\(format(weight: weight)) × \(amount)" }
        return previous.reps != nil ? "× \(amount)" : amount
    }

    private func format(weight kilograms: Double) -> String {
        WeightInput.displayValue(kilograms, unit: unit).formatted(.number.precision(.fractionLength(0...2)))
    }

    private var weightBinding: Binding<Double?> {
        Binding(get: {
            row.entered.weightKg.map { WeightInput.displayValue($0, unit: unit) }
        }, set: { value in
            let kilograms = value.flatMap { WeightInput.kilograms(from: "\($0)", unit: unit) }
            workouts.change { $0.updateSet(row.id) { $0.entered.weightKg = kilograms } }
        })
    }

    private func intBinding(_ field: WritableKeyPath<PlannedSet, Int?>) -> Binding<Int?> {
        let range = field == \PlannedSet.reps ? SetRanges.reps : SetRanges.seconds
        return Binding(get: {
            row.entered[keyPath: field]
        }, set: { value in
            let clamped = value.map { min(max($0, range.lowerBound), range.upperBound) }
            workouts.change { $0.updateSet(row.id) { $0.entered[keyPath: field] = clamped } }
        })
    }
}

private extension View {
    func field(width: CGFloat) -> some View {
        multilineTextAlignment(.center)
            .padding(.vertical, 6)
            .frame(width: width)
            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 8))
    }
}

/// The rest at the bottom of the workout (DESIGN V3): time left, −10 / +10 / Skip, a green bar, the next set.
private struct RestPanel: View {
    @Environment(WorkoutController.self) private var workouts
    let rest: ActiveWorkout.Rest
    let next: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, rest.endsAt.timeIntervalSince(context.date))
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rest")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.rest)
                        Text(Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond)))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("−10") { workouts.adjustRest(by: -10) }
                            .accessibilityLabel("Minus 10 seconds")
                        Button("+10") { workouts.adjustRest(by: 10) }
                            .accessibilityLabel("Plus 10 seconds")
                        Button("Skip") { workouts.skipRest() }
                    }
                    .buttonStyle(.bordered)
                    .monospacedDigit()
                }
                ProgressView(value: Double(rest.totalSeconds) - left, total: Double(max(1, rest.totalSeconds)))
                    .tint(Color.rest)
                if let next {
                    Text(next)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
    }
}
