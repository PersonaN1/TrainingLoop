import SwiftData
import SwiftUI
import TrainingLoopCore

/// Template editor sheet (SPEC D3–D5, DESIGN V6): works on a copy, writes only on Done.
struct TemplateEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var allExercises: [Exercise]

    /// nil creates a new template.
    let template: Template?
    private let originalName: String
    private let original: TemplateDefinition

    @State private var name: String
    @FocusState private var nameFocused: Bool
    @State private var draft: TemplateDefinition
    @State private var editMode = EditMode.inactive
    @State private var selection = Set<UUID>()
    @State private var picker: PickerTarget?
    @State private var setEditing: SetEditing?
    @State private var restEditing: RestEditing?
    @State private var mergeError: TemplateDefinition.MergeError?
    @State private var confirmingDiscard = false

    init(template: Template?) {
        self.template = template
        let definition = template?.definition ?? TemplateDefinition()
        originalName = template?.name ?? ""
        original = definition
        _name = State(initialValue: originalName)
        _draft = State(initialValue: definition)
    }

    private var hasChanges: Bool { name != originalName || draft != original }
    private var lookup: ExerciseLookup { ExerciseLookup(allExercises) }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                Section {
                    // An empty name falls back to "New Workout" on save, as the prompt shows.
                    TextField("Name", text: $name, prompt: Text("New Workout"))
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .nameLimit($name)
                }
                if editMode.isEditing {
                    reorderSection
                } else {
                    ForEach(draft.items) { item in
                        itemSection(item)
                    }
                }
                if draft.items.isEmpty {
                    Section {
                        Text("Add exercises from the catalog. Sets and rest can be changed for each one.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .safeAreaInset(edge: .bottom) {
                // Over the keyboard the panel would cover half the screen.
                if !nameFocused { bottomPanel }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { confirmingDiscard = true } else { dismiss() }
                    }
                    .confirmationDialog("Discard changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                        Button("Discard Changes", role: .destructive) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                        .fontWeight(.semibold)
                        .disabled(draft.items.isEmpty)
                }
            }
            .sheet(item: $picker) { target in
                ExercisePickerView(mode: target.mode) { apply(target, picked: $0) }
            }
            .sheet(item: $setEditing) { editing in
                setSheet(editing)
            }
            .sheet(item: $restEditing) { editing in
                DurationSheet(title: editing.title, seconds: restSeconds(editing.kind), range: 0...600) {
                    setRest(editing.kind, seconds: $0)
                }
            }
            .alert(String(localized: "Can't merge these exercises"),
                   isPresented: Binding(get: { mergeError != nil }, set: { if !$0 { mergeError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(mergeErrorMessage)
            }
        }
        .interactiveDismissDisabled(hasChanges)
    }

    // MARK: Sections

    @ViewBuilder
    private func itemSection(_ item: TemplateItem) -> some View {
        switch item {
        case .exercise(let exercise):
            Section {
                exerciseRows(exercise, inSuperset: false)
            }
        case .superset(let superset):
            Section {
                ForEach(superset.exercises) { exercise in
                    exerciseRows(exercise, inSuperset: true)
                }
                restRow("Rest Within Round", seconds: superset.restWithinSeconds,
                        editing: RestEditing(kind: .within(superset.id)))
                restRow("Rest After Round", seconds: superset.restAfterSeconds,
                        editing: RestEditing(kind: .after(superset.id)))
            } header: {
                HStack {
                    Text("Superset")
                    Spacer()
                    Menu {
                        Button("Add Exercises", systemImage: "plus") { picker = .addToSuperset(superset.id) }
                        Button("Split Superset", systemImage: "rectangle.split.1x2") {
                            withAnimation { draft.splitSuperset(superset.id) }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle").imageScale(.large)
                    }
                    .textCase(nil)
                    .accessibilityLabel("Superset Options")
                }
            }
            .listRowBackground(SupersetRowBackground())
        }
    }

    @ViewBuilder
    private func exerciseRows(_ item: TemplateExercise, inSuperset: Bool) -> some View {
        let exercise = lookup[item.exerciseID]
        HStack {
            Text(lookup.name(item.exerciseID)).font(.headline)
            Spacer()
            Menu {
                Button("Replace", systemImage: "arrow.left.arrow.right") { picker = .replace(item.id) }
                Button("Duplicate", systemImage: "plus.square.on.square") {
                    withAnimation { draft.duplicateExercise(item.id) }
                }
                if inSuperset {
                    Button("Remove from Superset", systemImage: "arrow.down.right.square") {
                        withAnimation { draft.takeOutOfSuperset(item.id) }
                    }
                }
                Button("Delete", systemImage: "trash", role: .destructive) {
                    withAnimation { draft.removeExercise(item.id) }
                }
            } label: {
                Image(systemName: "ellipsis.circle").imageScale(.large)
            }
            .accessibilityLabel("Exercise Options")
        }
        ForEach(Array(item.sets.enumerated()), id: \.offset) { index, set in
            Button {
                setEditing = SetEditing(exerciseID: item.id, index: index)
            } label: {
                SetLine(number: index + 1, set: set, weighted: exercise?.weighted ?? (set.weightKg != nil),
                        unit: settings.weightUnit)
            }
            .tint(.primary)
            .deleteDisabled(item.sets.count == 1)
        }
        .onDelete { offsets in
            draft.updateExercise(item.id) { exercise in
                guard exercise.sets.count > offsets.count else { return }
                exercise.sets.remove(atOffsets: offsets)
            }
        }
        // Copies the last set (SPEC D4), so a pyramid only needs the changed value.
        Button("Add Set", systemImage: "plus") {
            draft.updateExercise(item.id) { exercise in
                exercise.sets.append(exercise.sets.last ?? .default(for: measure(of: exercise)))
            }
        }
        if !inSuperset {
            restRow("Rest", seconds: item.restSeconds, editing: RestEditing(kind: .exercise(item.id)))
        }
    }

    private func restRow(_ title: LocalizedStringKey, seconds: Int, editing: RestEditing) -> some View {
        Button { restEditing = editing } label: {
            LabeledContent(title, value: TemplateFormat.duration(seconds))
                .monospacedDigit()
        }
        .tint(.primary)
    }

    /// Select mode: one row per exercise, with a stripe on superset ones, to reorder and to merge (DESIGN V6).
    private var reorderSection: some View {
        Section {
            ForEach(draft.exercises) { exercise in
                let supersetID = draft.supersetID(containing: exercise.id)
                HStack {
                    Text(lookup.name(exercise.exerciseID))
                    Spacer()
                    Text(SetsSummary(exercise.sets).cardText)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .listRowBackground(supersetID == nil
                                   ? AnyView(Color(.secondarySystemGroupedBackground))
                                   : AnyView(SupersetRowBackground()))
                .deleteDisabled(true)
                // A dropped row keeps its old background unless it becomes a new row.
                .id("\(exercise.id)-\(supersetID?.uuidString ?? "")")
                .tag(exercise.id)
            }
            .onMove { draft.moveExercises(fromOffsets: $0, toOffset: $1) }
        } footer: {
            Text("Select neighbouring exercises to merge them into a superset. Drag to reorder; drop an exercise between two of a superset to add it there, or away from it to take it out.")
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            if editMode.isEditing {
                HStack {
                    Button("Cancel") { setSelecting(false) }
                    Spacer()
                    Button("Merge into Superset") { merge() }
                        .fontWeight(.semibold)
                        .disabled(selection.isEmpty)
                }
                .frame(minHeight: 44)
            } else {
                HStack(spacing: 12) {
                    Button { picker = .add } label: {
                        Label("Add Exercises", systemImage: "plus")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    Button { setSelecting(true) } label: {
                        Text("Select").frame(minHeight: 34)
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.items.isEmpty)
                }
            }
            if !draft.items.isEmpty {
                Text(TemplateFormat.summary(draft))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private func setSheet(_ editing: SetEditing) -> some View {
        if let item = draft.exercises.first(where: { $0.id == editing.exerciseID }),
           item.sets.indices.contains(editing.index) {
            let exercise = lookup[item.exerciseID]
            SetSheet(number: editing.index + 1, set: item.sets[editing.index], measure: measure(of: item),
                     weighted: exercise?.weighted ?? true, unit: settings.weightUnit,
                     canDelete: item.sets.count > 1) { result in
                draft.updateExercise(item.id) { exercise in
                    guard exercise.sets.indices.contains(editing.index) else { return }
                    if let result { exercise.sets[editing.index] = result } else { exercise.sets.remove(at: editing.index) }
                }
            }
        }
    }

    // MARK: Editing

    private func measure(of item: TemplateExercise) -> Measure {
        lookup[item.exerciseID]?.measure ?? (item.sets.first?.seconds != nil ? .time : .reps)
    }

    private func apply(_ target: PickerTarget, picked: [Exercise]) {
        switch target {
        case .add:
            draft.items.append(contentsOf: newExercises(picked).map(TemplateItem.exercise))
        case .addToSuperset(let id):
            draft.appendExercises(newExercises(picked), toSuperset: id)
        case .replace(let id):
            guard let exercise = picked.first else { return }
            draft.replaceExercise(id, with: exercise.id, measure: exercise.measure)
            if !exercise.weighted {
                draft.updateExercise(id) { item in
                    for index in item.sets.indices { item.sets[index].weightKg = nil }
                }
            }
        }
    }

    private func newExercises(_ picked: [Exercise]) -> [TemplateExercise] {
        picked.map { .new(exerciseID: $0.id, measure: $0.measure, restSeconds: settings.defaultRestSeconds) }
    }

    private func restSeconds(_ kind: RestEditing.Kind) -> Int {
        switch kind {
        case .exercise(let id): draft.exercises.first { $0.id == id }?.restSeconds ?? 0
        case .within(let id), .after(let id):
            draft.items.lazy.compactMap { item -> Int? in
                guard case .superset(let superset) = item, superset.id == id else { return nil }
                if case .within = kind { return superset.restWithinSeconds }
                return superset.restAfterSeconds
            }.first ?? 0
        }
    }

    private func setRest(_ kind: RestEditing.Kind, seconds: Int) {
        switch kind {
        case .exercise(let id): draft.updateExercise(id) { $0.restSeconds = seconds }
        case .within(let id): draft.updateSuperset(id) { $0.restWithinSeconds = seconds }
        case .after(let id): draft.updateSuperset(id) { $0.restAfterSeconds = seconds }
        }
    }

    private func setSelecting(_ selecting: Bool) {
        withAnimation {
            editMode = selecting ? .active : .inactive
            selection = []
        }
    }

    private func merge() {
        do {
            // 30 s between exercises as in the examples (SPEC D18); the usual rest after a round.
            try draft.mergeIntoSuperset(exerciseIDs: selection, restWithinSeconds: 30,
                                        restAfterSeconds: settings.defaultRestSeconds)
            setSelecting(false)
        } catch {
            mergeError = error
        }
    }

    private var mergeErrorMessage: String {
        switch mergeError {
        case .notContiguous: String(localized: "Select at least two neighbouring exercises.")
        case .alreadySuperset: String(localized: "These exercises already form a superset.")
        case nil: ""
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName: String
        if trimmed.isEmpty {
            let others = ((try? context.fetch(FetchDescriptor<Template>())) ?? []).filter { $0 !== template }.map(\.name)
            finalName = TemplateNaming.unique(String(localized: "New Workout"), among: others)
        } else {
            finalName = trimmed
        }
        if let template {
            template.name = finalName
            if template.definition != draft { template.definition = draft }
        } else {
            var last = FetchDescriptor<Template>(sortBy: [SortDescriptor(\.sortIndex, order: .reverse)])
            last.fetchLimit = 1
            let sortIndex = ((try? context.fetch(last))?.first?.sortIndex ?? -1) + 1
            context.insert(Template(name: finalName, definition: draft, sortIndex: sortIndex))
        }
        context.saveOrReport()
        dismiss()
    }
}

/// "1 · 8 reps · 60 kg"; an empty weight reads "last time's weight" in gray (DESIGN V6).
struct SetLine: View {
    let number: Int
    let set: PlannedSet
    let weighted: Bool
    let unit: WeightUnit

    var body: some View {
        HStack(spacing: 12) {
            Text(number.formatted())
                .foregroundStyle(.secondary)
                .frame(minWidth: 20, alignment: .leading)
            if let reps = set.reps {
                Text(TemplateFormat.reps(reps...reps))
            } else if let seconds = set.seconds {
                Text(TemplateFormat.duration(seconds))
            }
            Spacer()
            if weighted {
                if let weight = set.weightKg {
                    Text(unit.weightText(weight))
                } else {
                    Text("last time's weight", comment: "Empty planned weight; the previous time's weight is used")
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .monospacedDigit()
    }
}

private enum PickerTarget: Identifiable {
    case add
    case addToSuperset(UUID)
    /// A template exercise's ID.
    case replace(UUID)

    var id: String {
        switch self {
        case .add: "add"
        case .addToSuperset(let id): "superset-\(id)"
        case .replace(let id): id.uuidString
        }
    }

    var mode: ExercisePickerView.Mode {
        if case .replace = self { .replace } else { .add }
    }
}

private struct SetEditing: Identifiable {
    let id = UUID()
    /// A template exercise's ID.
    let exerciseID: UUID
    let index: Int
}

private struct RestEditing: Identifiable {
    enum Kind {
        case exercise(UUID)
        case within(UUID)
        case after(UUID)
    }

    let id = UUID()
    let kind: Kind

    var title: String {
        switch kind {
        case .exercise: String(localized: "Rest")
        case .within: String(localized: "Rest Within Round")
        case .after: String(localized: "Rest After Round")
        }
    }
}
