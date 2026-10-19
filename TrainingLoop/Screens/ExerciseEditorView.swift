import SwiftData
import SwiftUI
import TrainingLoopCore

/// Form values for a new or edited custom exercise; saved only on "Done".
struct ExerciseDraft: Identifiable {
    let id = UUID()
    /// The exercise being edited; nil for a new one.
    var exercise: Exercise?
    var name = ""
    var measure = Measure.reps
    var weighted = true
    var primaryGroup = MuscleGroup.fullBody
    var muscles: Set<Muscle> = []
    var bySide = false
    var equipment = Equipment.bodyweight
    var note = ""

    init(primaryGroup: MuscleGroup, equipment: Equipment) {
        self.primaryGroup = primaryGroup
        self.equipment = equipment
    }

    init(editing exercise: Exercise) {
        self.init(copying: exercise, name: exercise.name)
        self.exercise = exercise
    }

    /// A new custom exercise with everything but the name taken from `exercise` (SPEC D8: "duplicate").
    init(copying exercise: Exercise, name: String) {
        self.name = name
        measure = exercise.measure
        weighted = exercise.weighted
        primaryGroup = exercise.primaryGroup
        muscles = Set(exercise.muscles)
        bySide = exercise.bySide
        equipment = exercise.equipment
        note = exercise.note
    }
}

/// New or edited custom exercise (DESIGN V10). A built-in exercise gets its muscles, sides and note:
/// `BuiltinExerciseEditorView`.
struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]
    @State private var draft: ExerciseDraft
    /// The type can't change once the exercise is in history (SPEC D8), nor while the running workout
    /// has it: its sets would then be saved with the other type's values.
    @State private var measureLock: MeasureLock?

    private enum MeasureLock { case history, workout }

    private var measureLocked: Bool { measureLock != nil }

    /// Called with the saved exercise, after it is in the store.
    private let onSave: (Exercise) -> Void

    init(draft: ExerciseDraft, onSave: @escaping (Exercise) -> Void = { _ in }) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.name)
                        .nameLimit($draft.name)
                } footer: {
                    if nameProblem == .duplicate {
                        Text("An exercise with this name already exists.")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    if measureLocked {
                        LabeledContent("Exercise Type", value: draft.measure.title)
                    } else {
                        Picker("Exercise Type", selection: $draft.measure) {
                            ForEach(Measure.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                    }
                    Toggle("With Weight", isOn: $draft.weighted)
                } header: {
                    Text("What to Record in a Set")
                } footer: {
                    if measureLock == .history {
                        Text("The type can't change: the exercise is already in your history.")
                    } else if measureLock == .workout {
                        Text("The type can't change while the exercise is in the running workout.")
                    } else {
                        Text("Weight can be left empty — for example, pull-ups without a belt.")
                    }
                }

                BothSidesSection(isOn: $draft.bySide)

                Section("Description") {
                    Picker("Primary Group", selection: $draft.primaryGroup) {
                        ForEach(MuscleGroup.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Picker("Equipment", selection: $draft.equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Note — for example, seat setting", text: $draft.note, axis: .vertical)
                        .lineLimit(3...)
                        .noteLimit($draft.note)
                }

                Section {
                    MuscleChips(selection: $draft.muscles, primary: draft.primaryGroup)
                } header: {
                    Text("Target Muscles")
                }
            }
            .keyboardDismissButton()
            .navigationTitle(draft.exercise == nil ? "New Exercise" : "Edit Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .disabled(nameProblem != nil)
                }
            }
            .onAppear {
                guard let exercise = draft.exercise else { return }
                if context.hasHistory(exercise) {
                    measureLock = .history
                } else if workouts.uses(exercise.id) {
                    measureLock = .workout
                }
            }
        }
    }

    private var nameProblem: ExerciseName.Problem? {
        let others = allExercises.filter { $0 !== draft.exercise }.flatMap(\.allNames)
        return ExerciseName.problem(draft.name, otherNames: others)
    }

    private func save() {
        guard nameProblem == nil else { return }
        let exercise = draft.exercise ?? Exercise(name: "", measure: draft.measure, weighted: draft.weighted,
                                                  primaryGroup: draft.primaryGroup, equipment: draft.equipment)
        exercise.customName = ExerciseName.cleaned(draft.name)
        if !measureLocked { exercise.measure = draft.measure }
        exercise.weighted = draft.weighted
        exercise.primaryGroup = draft.primaryGroup
        // Kept in the catalog's order, not the order they were ticked.
        exercise.muscles = Muscle.allCases.filter(draft.muscles.contains)
        exercise.bySide = draft.bySide
        exercise.equipment = draft.equipment
        exercise.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.exercise == nil { context.insert(exercise) }
        context.saveOrReport()
        workouts.refit(context: context)
        onSave(exercise)
        dismiss()
    }
}

/// Target muscles as chips right in the form, the primary group's first: a tap ticks or unticks one.
/// Statistics count sets by them (SPEC D9).
private struct MuscleChips: View {
    @Binding var selection: Set<Muscle>
    let primary: MuscleGroup

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Muscle.ordered(Muscle.allCases, primary: primary), id: \.self) { muscle in
                let isSelected = selection.contains(muscle)
                Button {
                    if isSelected { selection.remove(muscle) } else { selection.insert(muscle) }
                } label: {
                    Text(muscle.title)
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .background(isSelected ? Color.accentColor : Color(.tertiarySystemFill), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// "Left and Right" (SPEC D23): each side does the set, volume counts both; a set can be split.
private struct BothSidesSection: View {
    @Binding var isOn: Bool

    var body: some View {
        Section {
            Toggle("Left and Right", isOn: $isOn)
        } footer: {
            Text("Two dumbbells or one arm at a time: a set counts for each side. When the sides differ, swipe the set right to split it into L and R.")
        }
    }
}

/// Lays subviews out in rows, starting a new row when the next one doesn't fit.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// What a built-in exercise lets change (SPEC D8, D9, D23, DESIGN V7): target muscles, sides, note.
struct BuiltinExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(WorkoutController.self) private var workouts
    let exercise: Exercise
    @State private var muscles: Set<Muscle>
    @State private var bySide: Bool
    @State private var note: String

    init(exercise: Exercise) {
        self.exercise = exercise
        _muscles = State(initialValue: Set(exercise.muscles))
        _bySide = State(initialValue: exercise.bySide)
        _note = State(initialValue: exercise.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    MuscleChips(selection: $muscles, primary: exercise.primaryGroup)
                } header: {
                    Text("Target Muscles")
                }
                BothSidesSection(isOn: $bySide)
                Section("Note") {
                    TextField("Note — for example, seat setting", text: $note, axis: .vertical)
                        .lineLimit(3...)
                        .noteLimit($note)
                }
            }
            .keyboardDismissButton()
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        exercise.muscles = Muscle.allCases.filter(muscles.contains)
                        exercise.bySide = bySide
                        exercise.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        context.saveOrReport()
                        workouts.refit(context: context)
                        dismiss()
                    }
                }
            }
        }
    }
}
