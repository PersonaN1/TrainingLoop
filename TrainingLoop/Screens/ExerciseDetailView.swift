import SwiftData
import SwiftUI
import TrainingLoopCore

/// An exercise's screen. For now: its description and the catalog actions (SPEC D8);
/// charts and records (SPEC D10, DESIGN V7) come with the history.
struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query private var allExercises: [Exercise]
    let exercise: Exercise
    let summary: ExerciseSummary?
    @State private var editor: ExerciseDraft?
    @State private var editingNote = false
    @State private var confirmingDelete = false
    @State private var limitReached = false
    /// Set when the exercise leaves the catalog; acted on once the screen is gone,
    /// so it never renders a deleted model.
    @State private var pendingRemoval: Removal?

    private enum Removal { case hide, archive, delete }

    var body: some View {
        List {
            Section {
                LabeledContent("Muscle Group", value: exercise.primaryGroup.title)
                if !exercise.secondaryGroups.isEmpty {
                    LabeledContent("Secondary", value: exercise.secondaryGroups.map(\.title)
                        .formatted(.list(type: .and, width: .narrow)))
                }
                LabeledContent("Equipment", value: exercise.equipment.title)
                LabeledContent("Exercise Type", value: exercise.measure.title)
                LabeledContent("With Weight", value: exercise.weighted ? String(localized: "Yes") : String(localized: "No"))
            } header: {
                if exercise.isCustom { CustomBadge() }
            }

            Section("History") {
                let summary = summary ?? ExerciseSummary(sets: [], measure: exercise.measure)
                if summary.workoutCount == 0 {
                    Text("Not done yet").foregroundStyle(.secondary)
                } else {
                    LabeledContent("Workouts", value: summary.workoutCount.formatted())
                    if let best = summary.best {
                        LabeledContent("Best", value: best.text(equipment: exercise.equipment, unit: settings.weightUnit))
                            .monospacedDigit()
                    }
                }
            }

            if !exercise.note.isEmpty {
                Section("Note") {
                    Text(exercise.note)
                }
            }

            Section {
                Button(exercise.isCustom ? "Duplicate" : "Duplicate as Custom", systemImage: "plus.square.on.square") {
                    duplicate()
                }
                if exercise.isCustom {
                    Button("Delete Exercise", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                        .confirmationDialog("Delete this exercise?", isPresented: $confirmingDelete,
                                            titleVisibility: .visible) {
                            Button("Delete", role: .destructive) { remove(keepsRecords ? .archive : .delete) }
                        } message: {
                            if keepsRecords {
                                Text("It's used in your history or templates, so it moves to the archive. You can restore it in Settings.")
                            }
                        }
                } else {
                    Button("Hide from Catalog", systemImage: "eye.slash") { remove(.hide) }
                }
            } footer: {
                if !exercise.isCustom {
                    Text("Hidden exercises can be shown again in Settings.")
                }
            }
        }
        .navigationTitle(exercise.name)
        .toolbar {
            Button(exercise.isCustom ? "Edit" : "Edit Note", systemImage: "pencil") {
                if exercise.isCustom { editor = ExerciseDraft(editing: exercise) } else { editingNote = true }
            }
        }
        .sheet(item: $editor) { draft in
            ExerciseEditorView(draft: draft)
        }
        .sheet(isPresented: $editingNote) {
            ExerciseNoteView(exercise: exercise)
        }
        .exerciseLimitAlert(isPresented: $limitReached)
        .onDisappear(perform: applyRemoval)
    }

    /// History and statistics stay, so the exercise is archived instead of deleted (SPEC D8).
    /// A template that uses it keeps it too.
    private var keepsRecords: Bool {
        context.hasHistory(exercise) || context.isInTemplate(exercise)
    }

    private func duplicate() {
        guard context.customExerciseCount() < Limits.maxCustomExercises else {
            limitReached = true
            return
        }
        let name = ExerciseName.copyName(of: exercise.name, otherNames: allExercises.flatMap(\.allNames))
        editor = ExerciseDraft(copying: exercise, name: name)
    }

    private func remove(_ removal: Removal) {
        pendingRemoval = removal
        dismiss()
    }

    private func applyRemoval() {
        guard let removal = pendingRemoval else { return }
        pendingRemoval = nil
        switch removal {
        case .hide: exercise.isHidden = true
        case .archive: exercise.isArchived = true
        case .delete: context.delete(exercise)
        }
        context.saveOrReport()
    }
}
