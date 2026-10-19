import SwiftData
import SwiftUI
import TrainingLoopCore

/// The Exercises tab: catalog with search and a filter, grouped by primary muscle group (SPEC D8, D13; DESIGN V10).
struct ExercisesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Exercise> { !$0.isHidden && !$0.isArchived })
    private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var filter = ExerciseFilter()
    @State private var summaries: [UUID: ExerciseSummary] = [:]
    /// The store changed since the summaries were made; they are made again when the tab shows.
    @State private var summariesStale = true
    @State private var editor: ExerciseDraft?
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            List {
                if filter.isActive {
                    ExerciseFilterChips(filter: $filter)
                }
                ForEach(sections, id: \.group) { section in
                    Section(section.group.title) {
                        ForEach(section.exercises) { exercise in
                            NavigationLink(value: exercise) { row(exercise) }
                        }
                    }
                }
            }
            .overlay { CatalogEmptyState(isEmpty: sections.isEmpty, search: searchText, filter: $filter) }
            .navigationTitle("Exercises")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise)
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { ExerciseFilterMenu(filter: $filter, offersDone: true) }
                // iOS 26+ merges neighbouring items into one glass capsule; keep "+" apart from the filter.
                if #available(iOS 26, *) {
                    ToolbarSpacer(.fixed, placement: .topBarTrailing)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Exercise", systemImage: "plus") { add() }
                }
            }
            .sheet(item: $editor) { draft in
                ExerciseEditorView(draft: draft)
            }
            .exerciseLimitAlert(isPresented: $limitReached)
            // Workouts happen in another tab; coming back here picks up their sets, only when something was saved.
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave, object: context)) { _ in
                summariesStale = true
            }
            .task {
                guard summariesStale else { return }
                summariesStale = false
                await loadSummaries()
            }
        }
    }

    private var sections: [CatalogSection] {
        CatalogSection.make(exercises, filter: filter, search: searchText,
                            done: Set(summaries.filter { $0.value.workoutCount > 0 }.keys))
    }

    private func row(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(exercise.name)
                if exercise.bySide { BothSidesBadge() }
                if exercise.isCustom { CustomBadge() }
            }
            Text(summary(exercise).line(equipment: exercise.equipment, unit: settings.weightUnit))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func summary(_ exercise: Exercise) -> ExerciseSummary {
        summaries[exercise.id] ?? ExerciseSummary(sets: [], measure: exercise.measure)
    }

    // MARK: Actions

    private func add() {
        if context.customExerciseCount() >= Limits.maxCustomExercises {
            limitReached = true
        } else {
            editor = ExerciseDraft(primaryGroup: filter.group ?? .fullBody, equipment: filter.equipment ?? .bodyweight)
        }
    }

    /// One pass over all recorded sets, in the background (TECH T12); cheaper than a query per row.
    private func loadSummaries() async {
        let measures = Dictionary(exercises.map { ($0.id, $0.measure) }, uniquingKeysWith: { first, _ in first })
        summaries = await HistoryReader.read(context.container) { await $0.exerciseSummaries(measures: measures) }
    }
}

#Preview {
    ExercisesView()
        .environment(AppSettings())
        .environment(WorkoutController(settings: AppSettings()))
        .modelContainer(for: Exercise.self, inMemory: true)
}
