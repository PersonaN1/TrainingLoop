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
    var secondaryGroups: Set<MuscleGroup> = []
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
        secondaryGroups = Set(exercise.secondaryGroups)
        equipment = exercise.equipment
        note = exercise.note
    }
}

/// New or edited custom exercise (DESIGN V10). A built-in exercise only gets a note: `ExerciseNoteView`.
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
                    SecondaryGroupChips(selection: $draft.secondaryGroups, primary: draft.primaryGroup)
                } header: {
                    Text("Secondary Groups")
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
            // The primary group is never also a secondary one.
            .onChange(of: draft.primaryGroup) { _, primary in draft.secondaryGroups.remove(primary) }
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
        exercise.secondaryGroups = MuscleGroup.allCases.filter(draft.secondaryGroups.contains)
        exercise.equipment = draft.equipment
        exercise.note = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.exercise == nil { context.insert(exercise) }
        context.saveOrReport()
        onSave(exercise)
        dismiss()
    }
}

/// Secondary muscle groups as chips right in the form: a tap ticks or unticks one.
/// Description only, not counted in statistics (SPEC D9).
private struct SecondaryGroupChips: View {
    @Binding var selection: Set<MuscleGroup>
    let primary: MuscleGroup

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(MuscleGroup.allCases.filter { $0 != primary }, id: \.self) { group in
                let isSelected = selection.contains(group)
                Button {
                    if isSelected { selection.remove(group) } else { selection.insert(group) }
                } label: {
                    Text(group.title)
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

/// The note of a built-in exercise, its only editable field (SPEC D8, DESIGN V7).
struct ExerciseNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let exercise: Exercise
    @State private var note: String

    init(exercise: Exercise) {
        self.exercise = exercise
        _note = State(initialValue: exercise.note)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Note — for example, seat setting", text: $note, axis: .vertical)
                    .lineLimit(5...)
                    .noteLimit($note)
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
                        exercise.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
                        context.saveOrReport()
                        dismiss()
                    }
                }
            }
        }
    }
}
