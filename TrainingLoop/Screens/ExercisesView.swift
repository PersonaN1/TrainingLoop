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
    @State private var editor: ExerciseDraft?
    @State private var limitReached = false

    var body: some View {
        NavigationStack {
            List {
                if filter.isActive {
                    chips
                }
                ForEach(sections, id: \.group) { section in
                    Section(section.group.title) {
                        ForEach(section.exercises) { exercise in
                            NavigationLink(value: exercise) { row(exercise) }
                        }
                    }
                }
            }
            .overlay { emptyState }
            .navigationTitle("Exercises")
            .navigationDestination(for: Exercise.self) { exercise in
                ExerciseDetailView(exercise: exercise, summary: summaries[exercise.id])
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Exercise", systemImage: "plus") { add() }
                }
            }
            .sheet(item: $editor) { draft in
                ExerciseEditorView(draft: draft)
            }
            .exerciseLimitAlert(isPresented: $limitReached)
            // Workouts happen in another tab; coming back here picks up their sets.
            .onAppear { loadSummaries() }
        }
    }

    private struct GroupSection {
        let group: MuscleGroup
        let exercises: [Exercise]
    }

    private var sections: [GroupSection] {
        let visible = exercises.filter { exercise in
            filter.matches(primaryGroup: exercise.primaryGroup, equipment: exercise.equipment,
                           isCustom: exercise.isCustom)
                && ExerciseSearch.matches(searchText, names: exercise.allNames)
        }
        let byGroup = Dictionary(grouping: visible, by: \.primaryGroup)
        return MuscleGroup.allCases.compactMap { group in
            guard let members = byGroup[group] else { return nil }
            let sorted = members.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return GroupSection(group: group, exercises: sorted)
        }
    }

    private func row(_ exercise: Exercise) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(exercise.name)
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

    // MARK: Filter

    private var filterMenu: some View {
        Menu {
            Picker("Muscle Group", selection: $filter.group) {
                Text("Any").tag(MuscleGroup?.none)
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    Text(group.title).tag(MuscleGroup?.some(group))
                }
            }
            .pickerStyle(.menu)
            Picker("Equipment", selection: $filter.equipment) {
                Text("Any").tag(Equipment?.none)
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Text(equipment.title).tag(Equipment?.some(equipment))
                }
            }
            .pickerStyle(.menu)
            Divider()
            Toggle("Only Custom", isOn: $filter.onlyCustom)
        } label: {
            HStack(spacing: 4) {
                if filter.isActive {
                    Text("Filter (\(filter.activeCount))").fontWeight(.semibold)
                } else {
                    Text("Filter")
                }
                Image(systemName: "chevron.down").font(.caption.weight(.semibold))
            }
        }
        .tint(filter.isActive ? Color.accentColor : .primary)
    }

    /// One chip per active condition; ✕ removes it (DESIGN V10).
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let group = filter.group {
                    FilterChip(title: group.title) { filter.group = nil }
                }
                if let equipment = filter.equipment {
                    FilterChip(title: equipment.title) { filter.equipment = nil }
                }
                if filter.onlyCustom {
                    FilterChip(title: String(localized: "Only Custom")) { filter.onlyCustom = false }
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var emptyState: some View {
        if sections.isEmpty {
            if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else if filter.isActive {
                ContentUnavailableView {
                    Label("No Matching Exercises", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Reset Filter") { filter = ExerciseFilter() }
                }
            }
        }
    }

    // MARK: Actions

    private func add() {
        if context.customExerciseCount() >= Limits.maxCustomExercises {
            limitReached = true
        } else {
            editor = ExerciseDraft(primaryGroup: filter.group ?? .fullBody, equipment: filter.equipment ?? .bodyweight)
        }
    }

    /// One pass over all recorded sets; cheaper than a query per row.
    private func loadSummaries() {
        let sets: [WorkoutSet]
        do {
            sets = try context.fetch(FetchDescriptor<WorkoutSet>())
        } catch {
            Persistence.report("Fetching sets failed", error)
            return
        }
        let measures = Dictionary(exercises.map { ($0.id, $0.measure) }, uniquingKeysWith: { first, _ in first })
        let byExercise = Dictionary(grouping: sets, by: \.exerciseID)
        summaries = byExercise.reduce(into: [:]) { result, item in
            let performed = item.value.map {
                PerformedSet(reps: $0.reps, seconds: $0.seconds, weightKg: $0.weightKg,
                             workoutStartedAt: $0.workoutStartedAt)
            }
            result[item.key] = ExerciseSummary(sets: performed, measure: measures[item.key] ?? .reps)
        }
    }
}

/// «своё» next to a custom exercise's name (DESIGN V10).
struct CustomBadge: View {
    var body: some View {
        Text("custom")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

private struct FilterChip: View {
    let title: String
    let remove: () -> Void

    var body: some View {
        Button(action: remove) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "xmark").font(.caption2.weight(.bold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove filter \(title)"))
    }
}

#Preview {
    ExercisesView()
        .environment(AppSettings())
        .modelContainer(for: Exercise.self, inMemory: true)
}
