import SwiftData
import SwiftUI
import TrainingLoopCore

/// An exercise's screen: chart, records and workouts (SPEC D10, DESIGN V7), its description
/// and the catalog actions (SPEC D8).
struct ExerciseDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]
    let exercise: Exercise
    /// Read in the background (TECH T12); nil until the first read is done.
    @State private var history: [HistoryReader.ExerciseWorkout]?
    @State private var stats = ExerciseStats(sessions: [])
    @State private var metric: ExerciseStats.Metric = .bestWeight
    @State private var period: ChartPeriod = .threeMonths
    @State private var showingEstimateInfo = false
    @State private var editor: ExerciseDraft?
    @State private var editingNote = false
    @State private var confirmingDelete = false
    @State private var limitReached = false
    /// Set when the exercise leaves the catalog; acted on once the screen is gone,
    /// so it never renders a deleted model.
    @State private var pendingRemoval: Removal?

    private enum Removal { case hide, archive, delete }

    private var metrics: [ExerciseStats.Metric] {
        ExerciseStats.Metric.available(measure: exercise.measure, weighted: exercise.weighted && stats.hasWeight)
    }

    var body: some View {
        List {
            if history == nil {
                Section {
                    ProgressView().frame(maxWidth: .infinity)
                }
            } else if stats.workoutCount == 0 {
                Section {
                    Text("Not done yet").foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ExerciseChart(stats: stats, metrics: metrics, equipment: exercise.equipment,
                                  unit: settings.weightUnit, metric: $metric, period: $period)
                }
                Section {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tile }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Personal Records")
                }
                let forReps = stats.bestWeightForReps
                if !forReps.isEmpty {
                    Section("Best Weight for Reps") {
                        ForEach(forReps, id: \.reps) { item in
                            LabeledContent {
                                VStack(alignment: .trailing) {
                                    Text(settings.weightUnit.weightText(item.best.value))
                                        .foregroundStyle(.primary)
                                    Text(StatsFormat.date(item.best.date)).font(.caption)
                                }
                            } label: {
                                Text(TemplateFormat.reps(item.reps...item.reps))
                            }
                            .monospacedDigit()
                        }
                    }
                }
                Section("Workouts") {
                    let history = history ?? []
                    ForEach(history.indices.reversed(), id: \.self) { index in
                        NavigationLink(value: WorkoutRoute(id: history[index].workoutID)) {
                            workoutRow(history[index], index: index)
                        }
                    }
                }
            }

            Section {
                LabeledContent("Muscle Group", value: exercise.primaryGroup.title)
                if !exercise.muscles.isEmpty {
                    LabeledContent("Target Muscles", value: exercise.muscles.titles)
                }
                LabeledContent("Equipment", value: exercise.equipment.title)
                LabeledContent("Exercise Type", value: exercise.measure.title)
                LabeledContent("With Weight", value: exercise.weighted ? String(localized: "Yes") : String(localized: "No"))
                if exercise.bySide {
                    LabeledContent("Left and Right", value: String(localized: "Yes"))
                }
            } header: {
                if exercise.isCustom { CustomBadge() }
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
        .navigationDestination(for: WorkoutRoute.self) { route in
            if let workout = context.model(for: route.id) as? Workout, !workout.isDeleted {
                ExerciseWorkoutRecord(workout: workout)
            }
        }
        // Again each time the screen shows: a workout may have been edited meanwhile.
        .task { await load() }
        .sheet(isPresented: $showingEstimateInfo) {
            EstimatedMaxInfoView()
        }
        .toolbar {
            Button("Edit", systemImage: "pencil") {
                if exercise.isCustom { editor = ExerciseDraft(editing: exercise) } else { editingNote = true }
            }
        }
        .sheet(item: $editor) { draft in
            ExerciseEditorView(draft: draft)
        }
        .sheet(isPresented: $editingNote) {
            BuiltinExerciseEditorView(exercise: exercise)
        }
        .exerciseLimitAlert(isPresented: $limitReached)
        .onDisappear(perform: applyRemoval)
    }

    private func load() async {
        guard !exercise.isDeleted else { return }
        let id = exercise.id
        let read = await HistoryReader.read(context.container) { await $0.exerciseHistory(id) }
        guard !Task.isCancelled else { return }
        history = read.workouts
        stats = read.stats
        if !metrics.contains(metric), let first = metrics.first { metric = first }
    }

    /// Best weight, ≈ 1RM, volume and max reps; without weight max reps; on time max time (V7).
    private var tiles: [RecordTile] {
        let unit = settings.weightUnit
        let equipment = exercise.equipment
        func caption(_ best: ExerciseStats.Highlight, withSet: Bool = false) -> String {
            guard withSet, let set = best.set else { return StatsFormat.date(best.date) }
            return StatsFormat.set(set, equipment: equipment, unit: unit) + " · " + StatsFormat.date(best.date)
        }
        var tiles: [RecordTile] = []
        if let best = stats.bestWeight, let set = best.set {
            tiles.append(RecordTile(title: String(localized: "Best Weight"),
                                    value: StatsFormat.set(set, equipment: equipment, unit: unit),
                                    caption: caption(best)))
        }
        if let best = stats.estimatedMax {
            tiles.append(RecordTile(title: String(localized: "Est. 1RM"), value: "≈ " + unit.weightText(best.value.rounded1()),
                                    caption: caption(best, withSet: true)) { showingEstimateInfo = true })
        }
        if exercise.weighted, let best = stats.bestVolume {
            tiles.append(RecordTile(title: String(localized: "Workout Volume"),
                                    value: HistoryFormat.volume(best.value, unit: unit), caption: caption(best)))
        }
        if let best = stats.maxReps {
            tiles.append(RecordTile(title: String(localized: "Max Reps"), value: Int(best.value).formatted(),
                                    caption: caption(best, withSet: exercise.weighted)))
        }
        if let best = stats.maxSeconds {
            tiles.append(RecordTile(title: String(localized: "Max Time"), value: TemplateFormat.duration(Int(best.value)),
                                    caption: caption(best)))
        }
        tiles.append(RecordTile(title: String(localized: "Workouts"), value: stats.workoutCount.formatted(),
                                caption: String(localized: "since \(StatsFormat.date(stats.sessions[0].date))")))
        return tiles
    }

    private func workoutRow(_ item: HistoryReader.ExerciseWorkout, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(StatsFormat.date(item.startedAt))
                    .font(.subheadline.weight(.semibold))
                Text(item.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                let records = stats.records[index].lines.count
                if records > 0 {
                    Text(verbatim: "🏆 \(records.formatted())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.recordText)
                        .accessibilityLabel(String(localized: "\(records) records"))
                }
            }
            Text(StatsFormat.sets(item.sets, equipment: exercise.equipment, unit: settings.weightUnit))
                .font(.subheadline)
                .monospacedDigit()
        }
    }

    /// History and statistics stay, so the exercise is archived instead of deleted (SPEC D8).
    /// A template or the running workout that uses it keeps it too.
    private var keepsRecords: Bool {
        context.hasHistory(exercise) || context.isInTemplate(exercise) || workouts.uses(exercise.id)
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

private struct WorkoutRoute: Hashable {
    let id: PersistentIdentifier
}

/// A workout opened from the exercise's list; deleting it goes back to the exercise first.
private struct ExerciseWorkoutRecord: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let workout: Workout

    var body: some View {
        WorkoutRecordView(workout: workout) {
            dismiss()
            context.deleteWorkouts([workout])
        }
    }
}

private extension Double {
    /// Estimates read better without hundredths: 93.33 → 93.3.
    func rounded1() -> Double { (self * 10).rounded() / 10 }
}
