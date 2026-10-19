import SwiftUI
import TrainingLoopCore

/// Catalog pieces shared by the Exercises tab and the exercise picker (DESIGN V6, V10).
struct CatalogSection {
    let group: MuscleGroup
    let exercises: [Exercise]

    /// Exercises that pass the filter and the search, grouped by primary group in catalog order,
    /// sorted by name inside a group. `done`: exercises with a finished workout, for "Only Done".
    static func make(_ exercises: [Exercise], filter: ExerciseFilter, search: String,
                     done: Set<UUID> = []) -> [CatalogSection] {
        let visible = exercises.filter { exercise in
            filter.matches(primaryGroup: exercise.primaryGroup, muscles: exercise.muscles, equipment: exercise.equipment,
                           isCustom: exercise.isCustom, isDone: done.contains(exercise.id))
                && ExerciseSearch.matches(search, names: exercise.allNames)
        }
        let byGroup = Dictionary(grouping: visible, by: \.primaryGroup)
        return MuscleGroup.allCases.compactMap { group in
            guard let members = byGroup[group] else { return nil }
            let sorted = members.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return CatalogSection(group: group, exercises: sorted)
        }
    }
}

/// "Filter ▾": muscle group and its target muscle, equipment, only custom, only done (DESIGN V10).
struct ExerciseFilterMenu: View {
    @Binding var filter: ExerciseFilter
    /// The picker doesn't know the history and has no "Only Done".
    var offersDone = false
    /// An icon instead of "Filter ▾", where the bar is short of room; filled while the filter is on.
    var iconOnly = false

    var body: some View {
        Menu {
            Picker("Muscle Group", selection: $filter.group) {
                Text("Any").tag(MuscleGroup?.none)
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    Text(group.title).tag(MuscleGroup?.some(group))
                }
            }
            .pickerStyle(.menu)
            if let group = filter.group, !group.muscles.isEmpty {
                Picker("Target Muscle", selection: $filter.muscle) {
                    Text("Any").tag(Muscle?.none)
                    ForEach(group.muscles, id: \.self) { muscle in
                        Text(muscle.title).tag(Muscle?.some(muscle))
                    }
                }
                .pickerStyle(.menu)
            }
            Picker("Equipment", selection: $filter.equipment) {
                Text("Any").tag(Equipment?.none)
                ForEach(Equipment.allCases, id: \.self) { equipment in
                    Text(equipment.title).tag(Equipment?.some(equipment))
                }
            }
            .pickerStyle(.menu)
            Divider()
            Toggle("Only Custom", isOn: $filter.onlyCustom)
            if offersDone {
                Toggle("Only Done", isOn: $filter.onlyDone)
            }
        } label: {
            if iconOnly {
                Label(filter.isActive ? "Filter (\(filter.activeCount))" : "Filter",
                      systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill"
                                                   : "line.3.horizontal.decrease")
                    .labelStyle(.iconOnly)
            } else {
                HStack(spacing: 4) {
                    if filter.isActive {
                        Text("Filter (\(filter.activeCount))").fontWeight(.semibold)
                    } else {
                        Text("Filter")
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }
            }
        }
        .tint(filter.isActive ? Color.accentColor : .primary)
    }
}

/// One chip per active condition; ✕ removes it. Goes first in the list, only while the filter is on.
struct ExerciseFilterChips: View {
    @Binding var filter: ExerciseFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let group = filter.group {
                    FilterChip(title: group.title) { filter.group = nil }
                }
                if let muscle = filter.muscle {
                    FilterChip(title: muscle.title) { filter.muscle = nil }
                }
                if let equipment = filter.equipment {
                    FilterChip(title: equipment.title) { filter.equipment = nil }
                }
                if filter.onlyCustom {
                    FilterChip(title: String(localized: "Only Custom")) { filter.onlyCustom = false }
                }
                if filter.onlyDone {
                    FilterChip(title: String(localized: "Only Done")) { filter.onlyDone = false }
                }
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
    }
}

/// Shown over an empty catalog: no search results, or nothing passes the filter.
struct CatalogEmptyState: View {
    let isEmpty: Bool
    let search: String
    @Binding var filter: ExerciseFilter

    var body: some View {
        if isEmpty {
            if !search.trimmingCharacters(in: .whitespaces).isEmpty {
                // Not `.search(text:)`: its "No Results for «…»" doesn't fit a line and gets cut.
                ContentUnavailableView {
                    Label("No Results", systemImage: "magnifyingglass")
                } description: {
                    Text("Check the spelling or try a different search.")
                }
            } else if filter.isActive {
                ContentUnavailableView {
                    Label("No Matching Exercises", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Reset Filter") { filter = ExerciseFilter() }
                }
            }
        }
    }
}

/// «своё» next to a custom exercise's name (DESIGN V10).
/// "L+R": a set counts for each side, volume ×2 (SPEC D23).
struct BothSidesBadge: View {
    var body: some View {
        Text("L+R", comment: "Badge of an exercise done by both sides")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .accessibilityLabel("Left and Right")
    }
}

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
