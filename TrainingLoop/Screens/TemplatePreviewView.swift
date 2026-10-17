import SwiftData
import SwiftUI
import TrainingLoopCore

/// A template read-only (DESIGN V6): its exercises, sets and rests; ✎ opens the editor.
struct TemplatePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]
    let template: Template
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var limitReached = false
    /// Deleting waits until the screen is gone, so it never renders a deleted model.
    @State private var pendingDelete = false

    var body: some View {
        let definition = template.definition
        let lookup = ExerciseLookup(allExercises)
        List {
            Section {
            } header: {
                Text(TemplateFormat.summary(definition))
                    .font(.subheadline)
                    .textCase(nil)
                    .monospacedDigit()
            }
            ForEach(definition.items) { item in
                switch item {
                case .exercise(let exercise):
                    Section {
                        exerciseRow(exercise, lookup: lookup)
                        LabeledContent("Rest", value: TemplateFormat.duration(exercise.restSeconds))
                            .monospacedDigit()
                    }
                case .superset(let superset):
                    Section {
                        ForEach(superset.exercises) { exerciseRow($0, lookup: lookup) }
                        LabeledContent("Rest Within Round", value: TemplateFormat.duration(superset.restWithinSeconds))
                            .monospacedDigit()
                        LabeledContent("Rest After Round", value: TemplateFormat.duration(superset.restAfterSeconds))
                            .monospacedDigit()
                    } header: {
                        let rounds = superset.exercises.map(\.sets.count).max() ?? 0
                        Text("Superset · \(rounds) rounds")
                    }
                    .listRowBackground(SupersetRowBackground())
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                workouts.start(template, context: context)
            } label: {
                Label("Start", systemImage: "play.fill")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
        .navigationTitle(template.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") { editing = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        if !context.duplicate(template) { limitReached = true }
                    }
                    ShareTextButton(text: TextExport(exercises: allExercises, unit: settings.weightUnit)
                        .template(name: template.name, definition: definition))
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .confirmationDialog("Delete this template?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        pendingDelete = true
                        dismiss()
                    }
                } message: {
                    Text("Workouts in History stay.")
                }
            }
        }
        .sheet(isPresented: $editing) {
            TemplateEditorView(template: template)
        }
        .templateLimitAlert(isPresented: $limitReached)
        .onDisappear {
            if pendingDelete {
                pendingDelete = false
                context.delete(template)
                context.saveOrReport()
            }
        }
    }

    private func exerciseRow(_ item: TemplateExercise, lookup: ExerciseLookup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(lookup.name(item.exerciseID)).font(.headline)
            Text(SetsSummary(item.sets).previewText(item.sets, unit: settings.weightUnit,
                                                    equipment: lookup[item.exerciseID]?.equipment))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
