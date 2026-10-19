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
    static let workouts = WorkoutController(settings: settings, context: container.mainContext, fileURL: workoutFileURL)

    private static var workoutFileURL: URL {
        #if DEBUG
        if TestLaunch.isTesting { return TestLaunch.workoutFileURL }
        #endif
        return WorkoutController.defaultFileURL
    }

    static let container: ModelContainer = {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                                           migrationPlan: TrainingLoopMigrationPlan.self,
                                           configurations: storeConfigurations)
        } catch {
            fatalError("Can't open the store: \(error)")
        }
        // Built-in exercises first: the example templates refer to them.
        BuiltinSeeder.addMissing(container.mainContext)
        MuscleMigration.runOnce(container.mainContext)
        ExampleSeeder.seedIfNeeded(container.mainContext)
        DefaultNames.relocalize(container.mainContext)
        RecordCounts.countOnce(container.mainContext)
        #if DEBUG
        SampleHistory.insertIfRequested(container.mainContext)
        #endif
        return container
    }()

    /// None is the default store.
    private static var storeConfigurations: [ModelConfiguration] {
        #if DEBUG
        if TestLaunch.isTesting { return [ModelConfiguration(isStoredInMemoryOnly: true)] }
        #endif
        return []
    }
}

#if DEBUG
/// Debug builds only: under tests the app keeps off the simulator's real store and workout in progress.
/// UI tests launch it with `-UITesting YES` (and settings as launch arguments); unit tests are hosted
/// by it and make stores of their own.
enum TestLaunch {
    static let isTesting = UserDefaults.standard.bool(forKey: "UITesting")
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// Removed at launch, so every run starts without a workout.
    static let workoutFileURL: URL = {
        let url = URL.temporaryDirectory.appending(path: "test-active-workout.json")
        try? FileManager.default.removeItem(at: url)
        return url
    }()
}
#endif
