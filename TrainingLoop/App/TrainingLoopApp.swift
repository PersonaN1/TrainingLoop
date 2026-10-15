import SwiftData
import SwiftUI

@main
struct TrainingLoopApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(AppModel.container)
    }
}

/// App-wide objects, created once: SwiftUI may build the App more than once, and an App Intent
/// may run before the App is built at all.
@MainActor
enum AppModel {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: Schema(versionedSchema: SchemaV1.self),
                                      migrationPlan: TrainingLoopMigrationPlan.self)
        } catch {
            fatalError("Can't open the store: \(error)")
        }
    }()
}
