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
    /// Finished exercises the user collapsed; nothing collapses by itself (DESIGN V3).
    @State private var collapsed = Set<UUID>()
    @State private var picker: PickerTarget?
    @State private var confirmingFinish = false
    @State private var reordering = false
    @State private var restExpanded = false

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
                            RestPanel(rest: rest, next: nextText(workout)) { restExpanded = true }
                        }
                    }
                    // Tapping the panel opens the rest over the whole screen (DESIGN V3); it closes when it ends.
                    .fullScreenCover(isPresented: Binding(get: { restExpanded && workouts.rest != nil },
                                                          set: { restExpanded = $0 })) {
                        if let rest = workouts.rest {
                            RestScreen(rest: rest, next: nextText(workout)) { restExpanded = false }
                        }
                    }
                    .sheet(isPresented: $reordering) {
                        WorkoutOrderView()
                    }
                    .task(id: workout.items.flatMap(\.exercises).map(\.exerciseID)) {
                        await workouts.loadHistory(context: context)
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
                    // The cover's binding doesn't write back when the rest ends; without this the next rest
                    // would open full screen by itself.
                    .onChange(of: workouts.rest == nil) { _, ended in
                        if ended { restExpanded = false }
                    }
                    .forgottenWorkoutAlert(whileOpen: true)
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
        let records = workouts.records.setIDs
        return ScrollViewReader { proxy in
            List {
                ForEach(Array(workout.items.enumerated()), id: \.element.id) { itemIndex, item in
                    switch item {
                    case .exercise(let exercise):
                        Section {
                            exerciseRows(exercise, lookup: lookup, next: next, records: records)
                        }
                    case .superset(let superset):
                        Section {
                            ForEach(superset.exercises) {
                                exerciseRows($0, lookup: lookup, next: next, records: records, inSuperset: true)
                            }
                        } header: {
                            Text(supersetTitle(superset, workout: workout, itemIndex: itemIndex))
                        }
                        .listRowBackground(SupersetRowBackground())
                    }
                }
                Section {
                    Button("Add Exercises", systemImage: "plus") { picker = .add }
                    if workout.items.flatMap(\.exercises).count > 1 {
                        Button("Change Order", systemImage: "arrow.up.arrow.down") { reordering = true }
                    }
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
                              records: Set<UUID>, inSuperset: Bool = false) -> some View {
        let stored = lookup[exercise.exerciseID]
        let measure = stored?.measure ?? .reps
        let weighted = stored?.weighted ?? false
        let finished = !exercise.sets.isEmpty && exercise.sets.allSatisfy(\.isDone)
        if finished && collapsed.contains(exercise.id) {
            // "Squat ✓ 4 sets"; a tap opens it again (DESIGN V3).
            Button {
                withAnimation { _ = collapsed.remove(exercise.id) }
            } label: {
                HStack {
                    Text(lookup.name(exercise.exerciseID)).font(.headline)
                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    if exercise.sets.contains(where: { records.contains($0.id) }) {
                        Image(systemName: "trophy.fill")
                            .font(.subheadline)
                            .foregroundStyle(Color.record)
                            .accessibilityLabel("Record")
                    }
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
                    Button("Change Order", systemImage: "arrow.up.arrow.down") { reordering = true }
                    if finished {
                        Button("Collapse", systemImage: "chevron.up") {
                            withAnimation { _ = collapsed.insert(exercise.id) }
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
                           unit: settings.weightUnit, isNext: set.id == next, isRecord: records.contains(set.id),
                           inSuperset: inSuperset)
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
            Text("#", comment: "Set number column").frame(width: SetRowView.numberWidth, alignment: .leading)
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
    static let numberWidth: CGFloat = 34

    let number: Int
    let row: ActiveWorkout.SetRow
    let measure: Measure
    let weighted: Bool
    let unit: WeightUnit
    let isNext: Bool
    /// The set beat a record when it was ticked: 🏆 in coral (D10, DESIGN V7).
    let isRecord: Bool
    let inSuperset: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                Text(number.formatted())
                    .foregroundStyle(.secondary)
                if isRecord {
                    Image(systemName: "trophy.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.record)
                        .accessibilityLabel("Record")
                }
            }
            .frame(width: Self.numberWidth, alignment: .leading)
            Text(lastTime)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
            if weighted {
                TextField("Weight", value: weightBinding, format: .number.grouping(.never).precision(.fractionLength(0...2)),
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
        row.canTick(measure: measure)
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
/// A tap on the time opens it over the whole screen.
private struct RestPanel: View {
    @Environment(WorkoutController.self) private var workouts
    let rest: ActiveWorkout.Rest
    let next: String?
    let expand: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = rest.left(at: context.date)
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Button(action: expand) {
                        VStack(alignment: .leading, spacing: 2) {
                            Label(rest.isPaused ? "Rest · Paused" : "Rest", systemImage: "arrow.up.left.and.arrow.down.right")
                                .labelStyle(TrailingIconLabelStyle())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.rest)
                            Text(RestFormat.time(left))
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText(countsDown: true))
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the rest full screen")
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

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon.font(.caption.weight(.bold))
        }
    }
}

/// The rest over the whole screen, green like SetLoop's workout screen (DESIGN V3): a ring with large digits,
/// −10 / pause / +10, Skip and the next set.
private struct RestScreen: View {
    @Environment(WorkoutController.self) private var workouts
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let rest: ActiveWorkout.Rest
    let next: String?
    let collapse: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = rest.left(at: context.date)
            ZStack {
                Color.rest.ignoresSafeArea()
                Group {
                    if verticalSizeClass == .compact {
                        HStack(spacing: 32) {
                            ring(left, size: 220)
                            VStack(spacing: 24) {
                                info
                                controls
                                skipButton
                            }
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(spacing: 28) {
                            Spacer()
                            info
                            ring(left, size: 280)
                            controls
                            Spacer()
                            skipButton
                        }
                    }
                }
                .foregroundStyle(.white)
                .tint(.white)
                .padding()
            }
            .overlay(alignment: .topLeading) {
                Button(action: collapse) {
                    Image(systemName: "chevron.down")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel("Collapse")
                .padding(.horizontal, 8)
            }
        }
    }

    private var info: some View {
        VStack(spacing: 6) {
            Text(rest.isPaused ? "Rest · Paused" : "Rest")
                .font(.largeTitle.weight(.bold))
            // Keeps its height when empty, so nothing below jumps.
            Text(next ?? " ")
                .font(.headline)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
    }

    private func ring(_ left: TimeInterval, size: CGFloat) -> some View {
        let progress = rest.totalSeconds > 0 ? left / Double(rest.totalSeconds) : 0
        return ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: progress)
            Text(RestFormat.time(left))
                .font(.system(size: size * 0.32, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .padding(24)
                .accessibilityLabel(Duration.seconds(left.rounded(.up)).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))
        }
        .frame(width: size, height: size)
    }

    // The row never changes layout, so a button never moves under the finger.
    private var controls: some View {
        HStack(spacing: 32) {
            Button { workouts.adjustRest(by: -10) } label: { controlCircle(Text("−10")) }
                .accessibilityLabel("Minus 10 seconds")
            Button { workouts.toggleRestPause() } label: {
                controlCircle(Image(systemName: rest.isPaused ? "play.fill" : "pause.fill"), size: 88)
            }
            .accessibilityLabel(rest.isPaused ? "Resume" : "Pause")
            Button { workouts.adjustRest(by: 10) } label: { controlCircle(Text("+10")) }
                .accessibilityLabel("Plus 10 seconds")
        }
    }

    private var skipButton: some View {
        Button { workouts.skipRest() } label: {
            Text("Skip")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 36)
                .frame(minHeight: 56)
                .background(.white.opacity(0.18), in: Capsule())
                .contentShape(Capsule())
        }
    }

    private func controlCircle(_ content: some View, size: CGFloat = 64) -> some View {
        content
            .font(.system(size: size * 0.32, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(width: size, height: size)
            .background(.white.opacity(0.18), in: Circle())
            .contentShape(Circle())
    }
}

enum RestFormat {
    /// "1:05": whole seconds, rounded up so 0:00 shows only at the end.
    static func time(_ left: TimeInterval) -> String {
        Duration.seconds(left.rounded(.up)).formatted(.time(pattern: .minuteSecond))
    }
}

/// "Change Order" (D6): drag exercises as in the template editor; supersets keep their stripe.
private struct WorkoutOrderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]

    var body: some View {
        NavigationStack {
            if let workout = workouts.workout {
                let lookup = ExerciseLookup(allExercises)
                List {
                    Section {
                        ForEach(workout.items.flatMap { item in item.exercises.map { (exercise: $0, item: item) } },
                                id: \.exercise.id) { row in
                            HStack {
                                Text(lookup.name(row.exercise.exerciseID))
                                Spacer()
                                Text(verbatim: "\(row.exercise.sets.filter(\.isDone).count)/\(row.exercise.sets.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            .listRowBackground(row.item.isSuperset
                                               ? AnyView(SupersetRowBackground())
                                               : AnyView(Color(.secondarySystemGroupedBackground)))
                            // A dropped row keeps its old background unless it becomes a new row.
                            .id("\(row.exercise.id)-\(row.item.isSuperset ? row.item.id.uuidString : "")")
                        }
                        .onMove { source, destination in
                            workouts.change { $0.moveExercises(fromOffsets: source, toOffset: destination) }
                        }
                    } footer: {
                        Text("Drag to reorder; drop an exercise between two of a superset to add it there, or away from it to take it out.")
                    }
                }
                .environment(\.editMode, .constant(.active))
                .navigationTitle("Change Order")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
    }
}
