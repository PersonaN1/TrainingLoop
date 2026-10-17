import SwiftData
import SwiftUI
import TrainingLoopCore

extension TextExport {
    /// In the interface language and the chosen unit (TECH T11).
    @MainActor
    init(exercises: [Exercise], unit: WeightUnit) {
        let lookup = ExerciseLookup(exercises)
        self.init(unit: unit, locale: .interface) { id in
            TextExport.ExerciseInfo(name: lookup.name(id), addsWeight: lookup[id]?.equipment == .bodyweight)
        }
    }
}

extension Locale {
    /// The app's language with the user's region: words match the interface, numbers the region.
    static var interface: Locale {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        var components = Locale.Language.Components(identifier: language)
        components.region = Locale.current.region
        return Locale(languageComponents: components)
    }
}

extension Workout {
    var exported: TextExport.Workout {
        TextExport.Workout(name: name, startedAt: startedAt, durationSeconds: durationSeconds, note: note,
                           definition: definition)
    }
}

/// "Share" in a ⋯ menu: the text goes to the system share sheet (SPEC D12).
struct ShareTextButton: View {
    let text: String

    var body: some View {
        ShareLink(item: text) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }
}

/// Text made only when the share sheet asks for it: a selection may hold thousands of workouts,
/// and building their text on every tap would hold up the list.
struct DeferredText: Transferable, Sendable {
    let make: @MainActor @Sendable () -> String

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation { (item: DeferredText) in await item.make() }
    }

    /// Chosen History workouts as one text, oldest first (SPEC D12).
    static func workouts(_ ids: Set<PersistentIdentifier>, container: ModelContainer, unit: WeightUnit) -> DeferredText {
        DeferredText {
            let context = container.mainContext
            let workouts = ids.compactMap { context.model(for: $0) as? Workout }.filter { !$0.isDeleted }
            let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            return TextExport(exercises: exercises, unit: unit).period(workouts.map(\.exported), interval: nil)
        }
    }
}
