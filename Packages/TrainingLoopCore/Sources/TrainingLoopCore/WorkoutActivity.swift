#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Live Activity / Dynamic Island data (TECH T8, DESIGN V11). A stub for now: the full state
/// (set plan, next exercise, superset) comes with the workout screen.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        /// Rest countdown target; nil while a set is in progress.
        public var restEnd: Date?
        /// Exercise name, already localized.
        public var exerciseName: String

        public var isResting: Bool { restEnd != nil }

        public init(restEnd: Date?, exerciseName: String) {
            self.restEnd = restEnd
            self.exerciseName = exerciseName
        }
    }

    public var workoutName: String
    public var startedAt: Date

    public init(workoutName: String, startedAt: Date) {
        self.workoutName = workoutName
        self.startedAt = startedAt
    }
}
#endif
