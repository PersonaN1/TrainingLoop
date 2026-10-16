import SwiftData
import SwiftUI

@main
struct TrainingLoopApp: App {
    @State private var settings = AppModel.settings
    @State private var workouts = AppModel.workouts

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(workouts)
                .preferredColorScheme(settings.theme.colorScheme)
        }
        .modelContainer(AppModel.container)
    }
}

/// App-wide objects, created once: SwiftUI may build the App more than once, and an App Intent
/// may run before the App is built at all.
@MainActor
enum AppModel {
    static let settings = AppSettings()
    static let workouts = WorkoutController(settings: settings, context: container.mainContext)

    static let container: ModelContainer = {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                                           migrationPlan: TrainingLoopMigrationPlan.self)
        } catch {
            fatalError("Can't open the store: \(error)")
        }
        // Built-in exercises first: the example templates refer to them.
        BuiltinSeeder.addMissing(container.mainContext)
        ExampleSeeder.seedIfNeeded(container.mainContext)
        DefaultNames.relocalize(container.mainContext)
        #if DEBUG
        SampleHistory.insertIfRequested(container.mainContext)
        #endif
        return container
    }()
}
