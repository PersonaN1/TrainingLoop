import SwiftData
import SwiftUI
import TrainingLoopCore

/// A finished workout from History: totals, note, exercises and their sets, editing and "Repeat"
/// (SPEC D16, DESIGN V9).
struct WorkoutRecordView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]
    let workout: Workout
    let delete: () -> Void
    @State private var confirmingDelete = false
    @State private var editing = false

    var body: some View {
        // A deleted model must not be read; the screen is about to close anyway.
        if workout.isDeleted || workout.modelContext == nil {
            Color.clear
        } else {
            content
        }
    }

    private var content: some View {
        let lookup = ExerciseLookup(allExercises)
        return List {
            Section {
                LabeledContent("Started", value: workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: HistoryFormat.duration(workout.durationSeconds))
                LabeledContent("Volume", value: HistoryFormat.volume(workout.totalVolumeKg, unit: settings.weightUnit))
                LabeledContent("Sets", value: workout.totalSets.formatted())
                if workout.recordCount > 0 {
                    LabeledContent("New Records", value: "🏆 \(workout.recordCount.formatted())")
                }
            }
            .monospacedDigit()
            if !workout.note.isEmpty {
                Section("Note") {
                    Text(workout.note)
                }
            }
            ForEach(Array(workout.entryGroups.enumerated()), id: \.offset) { _, group in
                if group.count > 1 {
                    Section {
                        ForEach(group) { entryRows($0, lookup: lookup) }
                    } header: {
                        Text("Superset")
                    }
                    .listRowBackground(SupersetRowBackground())
                } else if let entry = group.first {
                    Section {
                        entryRows(entry, lookup: lookup)
                    }
                }
            }
            Section {
                Button("Repeat Workout", systemImage: "arrow.clockwise") {
                    workouts.repeatWorkout(workout, context: context)
                }
                .disabled(workouts.workout != nil)
            } footer: {
                if workouts.workout != nil {
                    Text("Finish the current workout to start this one again.")
                }
            }
        }
        .navigationTitle(workout.name)
        .sheet(isPresented: $editing) {
            TemplateEditorView(record: workout)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit", systemImage: "pencil") { editing = true }
            }
            // Separate buttons, not one glass capsule (iOS 26), as elsewhere in the app.
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Repeat Workout", systemImage: "arrow.clockwise") {
                        workouts.repeatWorkout(workout, context: context)
                    }
                    .disabled(workouts.workout != nil)
                    ShareTextButton(text: TextExport(exercises: allExercises, unit: settings.weightUnit)
                        .workout(workout.exported))
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .confirmationDialog("Delete this workout?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) {
                        delete()
                    }
                } message: {
                    Text("Its sets leave the exercise statistics.")
                }
            }
        }
    }

    @ViewBuilder
    private func entryRows(_ entry: WorkoutEntry, lookup: ExerciseLookup) -> some View {
        HStack(spacing: 6) {
            Text(lookup.name(entry.exerciseID)).font(.headline)
            if lookup[entry.exerciseID]?.bySide == true { BothSidesBadge() }
        }
        let sets = (entry.sets ?? []).sorted { $0.order < $1.order }
        if sets.isEmpty {
            Text("No sets done").foregroundStyle(.secondary)
        }
        ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
            SetLine(number: index + 1, set: set.planned, weighted: set.weightKg != nil, lastWeightKnown: false,
                    unit: settings.weightUnit)
        }
    }
}
