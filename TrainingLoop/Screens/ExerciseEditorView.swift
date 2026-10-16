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

    init(draft: ExerciseDraft) {
        _draft = State(initialValue: draft)
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
                    NavigationLink {
                        SecondaryGroupsView(selection: $draft.secondaryGroups, primary: draft.primaryGroup)
                    } label: {
                        LabeledContent("Secondary", value: secondaryText)
                    }
                    Picker("Equipment", selection: $draft.equipment) {
                        ForEach(Equipment.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    TextField("Note — for example, seat setting", text: $draft.note, axis: .vertical)
                        .lineLimit(3...)
                        .noteLimit($draft.note)
                }
            }
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

    private var secondaryText: String {
        let groups = MuscleGroup.allCases.filter(draft.secondaryGroups.contains)
        return groups.isEmpty ? String(localized: "None") : groups.map(\.title).formatted(.list(type: .and, width: .narrow))
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
        dismiss()
    }
}

/// Secondary muscle groups: description only, not counted in statistics (SPEC D9).
private struct SecondaryGroupsView: View {
    @Binding var selection: Set<MuscleGroup>
    let primary: MuscleGroup

    var body: some View {
        List(MuscleGroup.allCases.filter { $0 != primary }, id: \.self) { group in
            Button {
                if selection.contains(group) { selection.remove(group) } else { selection.insert(group) }
            } label: {
                HStack {
                    Text(group.title).foregroundStyle(Color.primary)
                    Spacer()
                    if selection.contains(group) {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }
                }
            }
            .accessibilityAddTraits(selection.contains(group) ? .isSelected : [])
        }
        .navigationTitle("Secondary Groups")
        .navigationBarTitleDisplayMode(.inline)
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
