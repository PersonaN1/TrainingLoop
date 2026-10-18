import SwiftData
import SwiftUI
import TrainingLoopCore

/// The catalog as a picker (DESIGN V6): search, filter and several exercises at once, "Add (N)";
/// or exactly one for "Replace". "+" creates a custom exercise right here; it comes back picked.
/// The bar holds icons only (✕, filter): text buttons squeezed the title down to "Add…".
/// "Create Exercise" heads the list.
struct ExercisePickerView: View {
    enum Mode {
        case add
        case replace
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { !$0.isHidden && !$0.isArchived })
    private var exercises: [Exercise]
    let mode: Mode
    /// Picked exercises, in the order they were ticked.
    let pick: ([Exercise]) -> Void
    @State private var searchText = ""
    @State private var filter = ExerciseFilter()
    @State private var picked: [Exercise] = []
    @State private var editor: ExerciseDraft?
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Create Exercise", systemImage: "plus") { newExercise() }
                }
                if filter.isActive {
                    ExerciseFilterChips(filter: $filter)
                }
                ForEach(sections, id: \.group) { section in
                    Section(section.group.title) {
                        ForEach(section.exercises) { exercise in
                            row(exercise)
                        }
                    }
                }
            }
            .overlay { CatalogEmptyState(isEmpty: sections.isEmpty, search: searchText, filter: $filter) }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(mode == .add ? "Add Exercises" : "Replace Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) { ExerciseFilterMenu(filter: $filter, iconOnly: true) }
            }
            .exerciseLimitAlert(isPresented: $limitReached)
            .sheet(item: $editor) { draft in
                ExerciseEditorView(draft: draft) { created in
                    switch mode {
                    case .replace:
                        pick([created])
                        dismiss()
                    case .add:
                        picked.append(created)
                        searchText = ""
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if mode == .add {
                    Button {
                        pick(picked)
                        dismiss()
                    } label: {
                        Text("Add (\(picked.count))")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(picked.isEmpty)
                    .padding()
                }
            }
        }
    }

    /// Starts with the search text as the name and the filter's group and equipment.
    private func newExercise() {
        if context.customExerciseCount() >= Limits.maxCustomExercises {
            limitReached = true
            return
        }
        var draft = ExerciseDraft(primaryGroup: filter.group ?? .fullBody, equipment: filter.equipment ?? .bodyweight)
        draft.name = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        editor = draft
    }

    private var sections: [CatalogSection] {
        CatalogSection.make(exercises, filter: filter, search: searchText)
    }

    private func row(_ exercise: Exercise) -> some View {
        let isPicked = picked.contains { $0 === exercise }
        return Button {
            switch mode {
            case .replace:
                pick([exercise])
                dismiss()
            case .add:
                if isPicked { picked.removeAll { $0 === exercise } } else { picked.append(exercise) }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(exercise.name)
                        if exercise.isCustom { CustomBadge() }
                    }
                    Text(exercise.equipment.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.primary)
                Spacer()
                if mode == .add {
                    Image(systemName: isPicked ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isPicked ? Color.accentColor : Color.secondary)
                }
            }
        }
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }
}
