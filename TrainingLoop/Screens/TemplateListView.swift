import SwiftData
import SwiftUI
import TrainingLoopCore

/// The Workouts tab: template cards (SPEC D13, DESIGN V5), as SetLoop's timer list.
struct TemplateListView: View {
    @Environment(\.modelContext) private var context
    @Environment(WorkoutController.self) private var workouts
    @Query(sort: \Template.sortIndex) private var templates: [Template]
    @Query private var allExercises: [Exercise]

    @State private var editMode = EditMode.inactive
    @State private var selection = Set<PersistentIdentifier>()
    /// The row whose delete confirmation is showing.
    @State private var pendingDelete: PersistentIdentifier?
    @State private var editor: TemplateEditorTarget?
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if !editMode.isEditing {
                    Section {
                        Button("Start Free Workout", systemImage: "play.fill") { workouts.startFree() }
                            .fontWeight(.semibold)
                    }
                }
                // Rows are tagged by persistent ID to match the selection (the model's own `id` is a UUID).
                ForEach(templates, id: \.persistentModelID) { template in
                    NavigationLink(value: template) {
                        TemplateCard(template: template, lookup: ExerciseLookup(allExercises)) {
                            workouts.start(template, context: context)
                        }
                    }
                    .swipeActions {
                        // No destructive role: it would remove the row before the confirmation.
                        Button("Delete", systemImage: "trash") { pendingDelete = template.persistentModelID }
                            .tint(.red)
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(template) }
                            .tint(.gray)
                        Button("Edit", systemImage: "pencil") { editor = .edit(template) }
                            .tint(.orange)
                    }
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { editor = .edit(template) }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(template) }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            pendingDelete = template.persistentModelID
                        }
                    }
                    // On the row, so the iOS 26+ popover points at the template being deleted.
                    .confirmationDialog(
                        "Delete this template?",
                        isPresented: Binding(
                            get: { pendingDelete == template.persistentModelID },
                            set: { if !$0 { pendingDelete = nil } }
                        ),
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) { context.delete(ids: [template.persistentModelID]) }
                    } message: {
                        Text("Workouts in History stay.")
                    }
                }
                .onMove(perform: move)
            }
            .listRowSpacing(12)
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("No Templates", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("A template is a plan of one workout: exercises, sets and rest.")
                    } actions: {
                        Button("New Template") { add() }
                    }
                }
            }
            .navigationTitle("Workouts")
            .navigationDestination(for: Template.self) { TemplatePreviewView(template: $0) }
            .toolbar {
                if !editMode.isEditing {
                    // iOS 26+ merges neighbouring items into one glass capsule; keep "+" on its own.
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Template", systemImage: "plus") { add() }
                    }
                }
            }
            .selectionToolbar(
                editMode: $editMode,
                selection: $selection,
                allIDs: templates.map(\.persistentModelID),
                confirmationTitle: { Text("Delete \($0) templates?") },
                delete: { context.delete(ids: $0) }
            )
            .sheet(item: $editor) { target in
                TemplateEditorView(template: target.template)
            }
            .templateLimitAlert(isPresented: $limitReached)
        }
    }

    private func add() {
        if templates.count >= Limits.maxTemplates { limitReached = true } else { editor = .new }
    }

    private func duplicate(_ template: Template) {
        if !context.duplicate(template) { limitReached = true }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = templates
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in ordered.enumerated() where template.sortIndex != index {
            template.sortIndex = index
        }
        context.saveOrReport()
    }
}

/// Name, up to six exercises with "sets×reps", then "…N more"; duration estimate and last time (DESIGN V5).
private struct TemplateCard: View {
    let template: Template
    let lookup: ExerciseLookup
    let start: () -> Void
    private static let maxRows = 6

    var body: some View {
        let definition = template.definition
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(template.name).font(.headline)
                Spacer()
                // ▶ starts at once; a tap elsewhere opens the preview (DESIGN V5).
                Button(action: start) {
                    Image(systemName: "play.fill")
                        .font(.footnote)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.accentColor, in: .circle)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Start")
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(visibleGroups(definition), id: \.id) { group in
                    HStack(spacing: 8) {
                        if group.isSuperset {
                            Capsule().fill(Color.accentColor).frame(width: 3)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(group.exercises) { exercise in
                                HStack {
                                    Text(lookup.name(exercise.exerciseID)).lineLimit(1)
                                    Spacer()
                                    Text(SetsSummary(exercise.sets).cardText)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
                let hidden = definition.exercises.count - Self.maxRows
                if hidden > 0 {
                    Text("…\(hidden) more").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
            Text(TemplateFormat.footer(definition, lastPerformedAt: template.lastPerformedAt))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }

    private struct Group {
        let id: UUID
        let isSuperset: Bool
        let exercises: [TemplateExercise]
    }

    /// Items cut to the first six exercises; a superset may be cut in the middle.
    private func visibleGroups(_ definition: TemplateDefinition) -> [Group] {
        var left = Self.maxRows
        var groups: [Group] = []
        for item in definition.items where left > 0 {
            let shown = Array(item.exercises.prefix(left))
            left -= shown.count
            groups.append(Group(id: item.id, isSuperset: item.isSuperset, exercises: shown))
        }
        return groups
    }
}

enum TemplateEditorTarget: Identifiable {
    case new
    case edit(Template)

    enum ID: Hashable {
        case new
        case edit(PersistentIdentifier)
    }

    var id: ID {
        switch self {
        case .new: .new
        case .edit(let template): .edit(template.persistentModelID)
        }
    }

    var template: Template? {
        if case .edit(let template) = self { template } else { nil }
    }
}

extension ModelContext {
    /// A copy right after the original, "Name (2)"; false at the template limit (SPEC D8).
    func duplicate(_ template: Template) -> Bool {
        let all = (try? fetch(FetchDescriptor<Template>(sortBy: [SortDescriptor(\.sortIndex)]))) ?? []
        guard all.count < Limits.maxTemplates else { return false }
        let name = ExerciseName.copyName(of: template.name, otherNames: all.map(\.name))
        for other in all where other.sortIndex > template.sortIndex {
            other.sortIndex += 1
        }
        insert(Template(name: name, definition: template.definition, sortIndex: template.sortIndex + 1))
        saveOrReport()
        return true
    }
}

extension View {
    /// Shown when adding a template is refused at the limit (SPEC D8).
    func templateLimitAlert(isPresented: Binding<Bool>) -> some View {
        alert("Template limit reached", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can keep up to \(Limits.maxTemplates) templates. Delete old ones to add a new one.")
        }
    }
}
