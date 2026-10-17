import SwiftData
import SwiftUI
import TrainingLoopCore

/// The History tab: finished workouts by day, or the summary (SPEC D11, D16; DESIGN V9).
struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Workout> { !$0.isActive }, sort: \Workout.startedAt, order: .reverse)
    private var workouts: [Workout]
    @Query private var allExercises: [Exercise]
    @State private var mode = Mode.records
    @State private var editMode = EditMode.inactive
    @State private var selection = Set<PersistentIdentifier>()
    @State private var deleting: PersistentIdentifier?
    @State private var path: [Route] = []
    @State private var adding = false
    @State private var exporting = false
    /// Rows are added as the list scrolls: a List of all 3000 workouts takes seconds to show (TECH T12).
    @State private var shownCount = Self.page
    private static let page = 200

    private enum Mode: Hashable { case records, summary }
    /// Not a bare id: in a selectable List a link with the selection's type selects instead of opening.
    private struct Route: Hashable { let id: PersistentIdentifier }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch mode {
                case .records: records
                case .summary:
                    HistorySummaryView { modePicker }
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: Route.self) { route in
                if let workout = context.model(for: route.id) as? Workout, !workout.isDeleted {
                    WorkoutRecordView(workout: workout) {
                        // Leave the screen first: a pushed screen whose model goes away doesn't close itself.
                        path.removeAll { $0 == route }
                        context.deleteWorkouts([workout])
                    }
                }
            }
            .toolbar {
                if !editMode.isEditing && mode == .records {
                    // iOS 26+ merges neighbouring items into one glass capsule; keep Export apart from Select.
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    // Workouts over a period as text (D12).
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Export Workouts", systemImage: "square.and.arrow.up") { exporting = true }
                            .disabled(workouts.isEmpty)
                    }
                    // iOS 26+ merges neighbouring items into one glass capsule; keep "+" on its own.
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // A workout done without the app (D16); never past the History limit.
                        Button("Add Workout", systemImage: "plus") { adding = true }
                            .disabled(workouts.count >= Limits.maxWorkouts)
                    }
                }
            }
            .sheet(isPresented: $adding) {
                TemplateEditorView(record: nil)
            }
            .sheet(isPresented: $exporting) {
                HistoryExportView(workouts: workouts, exercises: allExercises)
            }
            .selectionToolbar(
                editMode: $editMode, selection: $selection,
                allIDs: mode == .records ? workouts.map(\.persistentModelID) : [],
                confirmationTitle: { Text("Delete \($0) workouts?") },
                delete: { ids in context.deleteWorkouts(workouts.filter { ids.contains($0.persistentModelID) }) },
                share: { [container = context.container, unit = settings.weightUnit] ids in
                    DeferredText.workouts(ids, container: container, unit: unit)
                }
            )
        }
    }

    /// Under the large title, scrolling with the content (DESIGN V9).
    private var modePicker: some View {
        Picker("View", selection: $mode) {
            Text("Records").tag(Mode.records)
            Text("Summary").tag(Mode.summary)
        }
        .pickerStyle(.segmented)
        .disabled(editMode.isEditing)
    }

    private var records: some View {
        List(selection: $selection) {
            Section {
            } header: {
                modePicker
                    .textCase(nil)
                    .padding(.horizontal, -16)
            }
            if workouts.count >= Limits.historyWarningFrom {
                Section {
                    Label(String(localized: "\(max(0, Limits.maxWorkouts - workouts.count)) places left: delete old workouts or export them as text."),
                          systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                }
            }
            ForEach(days, id: \.date) { day in
                Section(HistoryFormat.day(day.date)) {
                    // Tagged by persistent ID to match the selection (the model's own `id` is a UUID).
                    ForEach(day.workouts, id: \.persistentModelID) { workout in
                        NavigationLink(value: Route(id: workout.persistentModelID)) { row(workout) }
                            .swipeActions {
                                Button("Delete", systemImage: "trash") { deleting = workout.persistentModelID }
                                    .tint(.red)
                            }
                            // On the row, so the iOS 26+ popover points at the workout being deleted.
                            .confirmationDialog(
                                "Delete this workout?",
                                isPresented: Binding(
                                    get: { deleting == workout.persistentModelID },
                                    set: { if !$0 { deleting = nil } }
                                ),
                                titleVisibility: .visible
                            ) {
                                Button("Delete", role: .destructive) { context.deleteWorkouts([workout]) }
                            } message: {
                                Text("Its sets leave the exercise statistics.")
                            }
                    }
                }
            }
            if workouts.count > shownCount {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .onAppear { shownCount += Self.page }
            }
        }
        .overlay {
            if workouts.isEmpty {
                ContentUnavailableView {
                    Label("No Workouts Yet", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("Start a workout — it will appear here")
                }
            }
        }
    }

    private var days: [(date: Date, workouts: [Workout])] {
        let calendar = Calendar.current
        var result: [(date: Date, workouts: [Workout])] = []
        for workout in workouts.prefix(shownCount) {
            let day = calendar.startOfDay(for: workout.startedAt)
            if result.last?.date == day {
                result[result.count - 1].workouts.append(workout)
            } else {
                result.append((day, [workout]))
            }
        }
        return result
    }

    private func row(_ workout: Workout) -> some View {
        let lookup = ExerciseLookup(allExercises)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.name).font(.headline)
                Spacer()
                // Records this workout set (DESIGN V9).
                if workout.recordCount > 0 {
                    Text(verbatim: "🏆 \(workout.recordCount.formatted())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.recordText)
                        .monospacedDigit()
                        .accessibilityLabel(Text("\(workout.recordCount) records"))
                }
            }
            Text(HistoryFormat.meta(workout, unit: settings.weightUnit))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            exerciseLine(workout, lookup: lookup)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }

    /// "Squat, Bench Press, Ro… +2": the names give way, the count stays.
    private func exerciseLine(_ workout: Workout, lookup: ExerciseLookup) -> some View {
        let names = workout.orderedEntries.map { lookup.name($0.exerciseID) }
        return HStack(spacing: 4) {
            Text(names.prefix(3).joined(separator: ", "))
                .lineLimit(1)
            if names.count > 3 {
                Text(verbatim: "+\(names.count - 3)")
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
    }
}

#Preview {
    HistoryView()
        .environment(AppSettings())
        .environment(WorkoutController(settings: AppSettings()))
        .modelContainer(for: [Workout.self, Exercise.self], inMemory: true)
}
