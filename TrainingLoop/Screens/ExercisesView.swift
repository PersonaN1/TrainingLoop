import SwiftData
import SwiftUI
import TipKit
import TrainingLoopCore

/// The Exercises tab: catalog with search and a filter, grouped by primary muscle group (SPEC D8, D13; DESIGN V10).
struct ExercisesView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutController.self) private var workouts
    @Query(filter: #Predicate<Exercise> { !$0.isHidden && !$0.isArchived })
    private var exercises: [Exercise]
    @State private var searchText = ""
    @State private var filter = ExerciseFilter()
    @State private var summaries: [UUID: ExerciseSummary] = [:]
    /// The store changed since the summaries were made; they are made again when the tab shows.
    @State private var summariesStale = true
    @State private var editor: ExerciseDraft?
    @State private var limitReached = false
    // Merging two exercises (SPEC D24, DESIGN V14).
    @State private var editMode = EditMode.inactive
    @State private var selection: Set<PersistentIdentifier> = []
    @State private var merging: MergePair?
    @State private var mergeProblem: MergeProblem?
    private let statsTip = ExerciseStatsTip()
    private let mergeTip = MergeExercisesTip()

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if filter.isActive {
                    ExerciseFilterChips(filter: $filter)
                }
                if !editMode.isEditing {
                    Section {
                        TipView(statsTip).tipRow()
                    }
                }
                ForEach(sections, id: \.group) { section in
                    Section(section.group.title) {
                        ForEach(section.exercises) { exercise in
                            NavigationLink(value: exercise) { row(exercise) }
                                .tag(exercise.persistentModelID)
                        }
                    }
                }
            }
            .overlay { CatalogEmptyState(isEmpty: sections.isEmpty, search: searchText, filter: $filter) }
            .navigationTitle("Exercises")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise)
                    .onAppear { statsTip.invalidate(reason: .actionPerformed) }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                if editMode.isEditing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { setEditing(false) }
                    }
                    // A hint, not a button: no glass capsule around it on iOS 26+.
                    if #available(iOS 26, *) {
                        ToolbarItem(placement: .bottomBar) { mergeHint }
                            .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .bottomBar) { mergeHint }
                    }
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.flexible, placement: .bottomBar)
                    } else {
                        ToolbarItem(placement: .bottomBar) { Spacer() }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button("Merge") { startMerge() }
                            .disabled(selection.count != 2)
                            // Its own dialog, so the iOS 26+ popover points at this button.
                            .confirmationDialog("Merge exercises?", isPresented: isMerging, titleVisibility: .visible,
                                                presenting: merging) { pair in
                                Button("Keep “\(pair.first.name)”") { merge(pair.second, into: pair.first) }
                                Button("Keep “\(pair.second.name)”") { merge(pair.first, into: pair.second) }
                            } message: { pair in
                                Text(mergeMessage(pair))
                            }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) { ExerciseFilterMenu(filter: $filter, offersDone: true) }
                    // iOS 26+ merges neighbouring items into one glass capsule; keep the buttons apart.
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Select") {
                            mergeTip.invalidate(reason: .actionPerformed)
                            setEditing(true)
                        }
                        .disabled(exercises.count < 2)
                        .popoverTip(mergeTip, arrowEdge: .top)
                    }
                    if #available(iOS 26, *) {
                        ToolbarSpacer(.fixed, placement: .topBarTrailing)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Exercise", systemImage: "plus") { add() }
                    }
                }
            }
            .toolbar(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
            .environment(\.editMode, $editMode)
            .onTipInvalidated(statsTip) { MergeExercisesTip.statsTipDone = true }
            .alert(item: $mergeProblem) { problem in
                Alert(title: Text("Can’t merge"), message: Text(problem.message), dismissButton: .default(Text("OK")))
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

    private var mergeHint: some View {
        Text("Select two exercises")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize()
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

    private func setEditing(_ editing: Bool) {
        withAnimation {
            editMode = editing ? .active : .inactive
            selection = []
        }
    }

    private var isMerging: Binding<Bool> {
        Binding { merging != nil } set: { if !$0 { merging = nil } }
    }

    private func startMerge() {
        let picked = exercises.filter { selection.contains($0.persistentModelID) }
        guard picked.count == 2 else { return }
        let first = picked[0], second = picked[1]
        switch ExerciseMerge.problem(first, second, workouts: workouts) {
        case .measure: mergeProblem = MergeProblem(first: first, second: second, kind: .measure)
        case .inWorkout: mergeProblem = MergeProblem(first: first, second: second, kind: .inWorkout)
        case nil: merging = MergePair(first: first, second: second)
        }
    }

    private func mergeMessage(_ pair: MergePair) -> String {
        let first = context.workoutCount(of: pair.first), second = context.workoutCount(of: pair.second)
        return String(localized: "Workouts with “\(pair.first.name)”: \(first), with “\(pair.second.name)”: \(second).")
            + "\n\n"
            + String(localized: "Workouts, templates and records of the other one move to the kept exercise. This can’t be undone.")
    }

    private func merge(_ other: Exercise, into kept: Exercise) {
        merging = nil
        ExerciseMerge.merge(other, into: kept, context: context)
        setEditing(false)
        // The kept row shows the joined history right away, not on the next visit to the tab.
        Task {
            summariesStale = false
            await loadSummaries()
        }
    }

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

private struct MergePair {
    let first: Exercise
    let second: Exercise
}

private struct MergeProblem: Identifiable {
    let first: Exercise
    let second: Exercise
    let kind: ExerciseMerge.Problem
    var id: String { "\(first.id)-\(second.id)" }

    var message: String {
        switch kind {
        case .measure:
            String(localized: "“\(first.name)” and “\(second.name)” are measured differently: one in reps, the other in time.")
        case .inWorkout:
            String(localized: "One of them is in the workout in progress. Finish the workout first.")
        }
    }
}

#Preview {
    ExercisesView()
        .environment(AppSettings())
        .environment(WorkoutController(settings: AppSettings()))
        .modelContainer(for: Exercise.self, inMemory: true)
}
