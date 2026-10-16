import SwiftData
import SwiftUI
import TrainingLoopCore

/// After "Finish" (SPEC D6, D11, D16; DESIGN V8): totals, name and note, "Update template" or
/// "Save as template", new records (🏆), then Save or Don't save.
struct WorkoutSummaryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workouts
    @Query private var allExercises: [Exercise]
    @Query private var templates: [Template]
    @State private var name = ""
    @State private var note = ""
    @State private var updateTemplate = false
    @State private var saveAsTemplate = false
    @State private var confirmingDiscard = false
    @State private var saveFailed = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            if let workout = workouts.workout, let endedAt = workouts.finishingAt {
                form(workout, endedAt: endedAt)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            workouts.loadHistory(context: context)
            guard !loaded, let workout = workouts.workout else { return }
            loaded = true
            name = workout.name
        }
    }

    private func form(_ workout: ActiveWorkout, endedAt: Date) -> some View {
        let done = workout.doneItems
        let sets = done.flatMap(\.exercises).flatMap(\.sets)
        let volume = sets.reduce(0) { $0 + WorkoutVolume.of(weightKg: $1.value.weightKg, reps: $1.value.reps) }
        let template = workout.templateID.flatMap { id in templates.first { $0.id == id } }
        let historyCount = context.finishedWorkoutCount()
        return Form {
            Section {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.rest)
                    Text(workout.name).font(.headline)
                    Text(HistoryFormat.duration(Int(endedAt.timeIntervalSince(workout.startedAt))))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    StatTile(title: "Volume", value: HistoryFormat.totalVolume(volume, unit: settings.weightUnit))
                    StatTile(title: "Sets", value: sets.count.formatted())
                    StatTile(title: "Exercises", value: done.flatMap(\.exercises).count.formatted())
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            let records = workouts.records.records
            if !records.isEmpty {
                let lookup = ExerciseLookup(allExercises)
                Section {
                    ForEach(Array(records.enumerated()), id: \.offset) { _, record in
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "\(lookup.name(record.exerciseID)) · \(record.metric.title)")
                            Spacer()
                            Text(value(of: record))
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.recordText)
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                } header: {
                    Text("🏆 New Records")
                }
            }
            if let groups = groupsLine(done) {
                Section("Sets by Muscle Group") {
                    Text(groups).font(.subheadline)
                }
            }
            Section {
                TextField("Name", text: $name)
                    .nameLimit($name)
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(1...5)
            }
            if let template {
                if workout.compositionDiffers(from: template.definition) {
                    Section {
                        Toggle("Update Template", isOn: $updateTemplate)
                    } footer: {
                        Text("The exercises or sets differ from “\(template.name)”. Changed weights and reps don't count.")
                    }
                }
            } else if workout.templateID == nil {
                Section {
                    Toggle("Save as Template", isOn: $saveAsTemplate)
                        .disabled(templates.count >= Limits.maxTemplates)
                }
            }
            if historyCount >= Limits.historyWarningFrom {
                Section {
                    if let oldest = context.oldestWorkoutIfFull() {
                        Label(String(localized: "History is full: the workout of \(oldest.startedAt.formatted(date: .long, time: .omitted)) will be deleted."),
                              systemImage: "exclamationmark.triangle")
                    } else {
                        Label(String(localized: "\(max(0, Limits.maxWorkouts - historyCount)) places left: delete old workouts or export them as text."),
                              systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.subheadline)
            }
            Section {
                Button {
                    do {
                        try workouts.save(name: trimmedName(workout),
                                          note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                                          endedAt: endedAt, updateTemplate: updateTemplate,
                                          saveAsTemplate: saveAsTemplate, context: context)
                    } catch {
                        saveFailed = true
                    }
                } label: {
                    Text("Save")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                Button("Don't Save", role: .destructive) { confirmingDiscard = true }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .confirmationDialog("Don't save this workout?", isPresented: $confirmingDiscard,
                                        titleVisibility: .visible) {
                        Button("Don't Save", role: .destructive) { workouts.discard() }
                    } message: {
                        Text("Its sets will be lost.")
                    }
            }
        }
        .alert("Couldn't save the workout", isPresented: $saveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing is lost: the workout stays open. Try again.")
        }
        .navigationTitle("Results")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back to Workout") { dismiss() }
            }
        }
    }

    /// "100 kg × 5", "100 kg", "12", "1:30", "2,400 kg".
    private func value(of record: WorkoutRecords.Record) -> String {
        let unit = settings.weightUnit
        let set = record.set ?? PlannedSet()
        switch record.metric {
        case .weight:
            let weight = unit.weightText(set.weightKg ?? 0)
            return set.reps.map { "\(weight) × \($0)" } ?? weight
        case .weightForReps:
            return unit.weightText(set.weightKg ?? 0)
        case .reps:
            return (set.reps ?? 0).formatted()
        case .seconds:
            return RestFormat.time(TimeInterval(set.seconds ?? 0))
        case .volume:
            return HistoryFormat.volume(record.volumeKg ?? 0, unit: unit)
        }
    }

    private func trimmedName(_ workout: ActiveWorkout) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? workout.name : trimmed
    }

    /// "Quads 8 · Back 6 · Chest 3".
    private func groupsLine(_ items: [ActiveWorkout.Item]) -> String? {
        let lookup = ExerciseLookup(allExercises)
        var sets: [MuscleGroup: Int] = [:]
        for exercise in items.flatMap(\.exercises) {
            guard let group = lookup[exercise.exerciseID]?.primaryGroup else { continue }
            sets[group, default: 0] += exercise.sets.count
        }
        guard !sets.isEmpty else { return nil }
        return sets.sorted { $0.value == $1.value ? $0.key.title < $1.key.title : $0.value > $1.value }
            .map { "\($0.key.title) \($0.value)" }
            .joined(separator: " · ")
    }
}

extension RecordMetric {
    var title: String {
        switch self {
        case .weight: String(localized: "Weight")
        case .weightForReps(let reps): String(localized: "Weight for \(reps) reps")
        case .reps: String(localized: "Reps")
        case .seconds: String(localized: "Time")
        case .volume: String(localized: "Volume")
        }
    }
}
