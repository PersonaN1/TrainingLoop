import SwiftData

/// The stored models as first shipped. A changed model gets a new schema version and a migration stage.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Exercise.self, Template.self, Workout.self, WorkoutEntry.self, WorkoutSet.self]
    }
}

enum TrainingLoopMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
