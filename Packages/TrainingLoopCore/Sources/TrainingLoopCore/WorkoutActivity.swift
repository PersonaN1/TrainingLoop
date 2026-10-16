#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Live Activity / Dynamic Island data (TECH T8, DESIGN V11): the rest card or the set card.
/// Texts come localized from the app; the countdown runs in the system.
public struct WorkoutActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public struct Rest: Codable, Hashable, Sendable {
            public var start: Date
            public var end: Date
            /// Time left while paused; then `start` and `end` aren't counted down.
            public var pausedLeft: TimeInterval?

            public init(start: Date, end: Date, pausedLeft: TimeInterval?) {
                self.start = start
                self.end = end
                self.pausedLeft = pausedLeft
            }
        }

        /// The rest in progress; nil shows the set card.
        public var rest: Rest?
        /// The next set's exercise; nil when every set is ticked.
        public var exerciseName: String?
        public var setNumber: Int
        public var setCount: Int
        /// "62.5 kg × 8", "× 12", "45 s"; empty when nothing is planned.
        public var plan: String
        /// "Superset · next Pull-ups".
        public var supersetNext: String?
        /// The next set has values to tick with "Done" (D7).
        public var canComplete: Bool

        public var isResting: Bool { rest != nil }

        public init(rest: Rest?, exerciseName: String?, setNumber: Int, setCount: Int, plan: String,
                    supersetNext: String?, canComplete: Bool) {
            self.rest = rest
            self.exerciseName = exerciseName
            self.setNumber = setNumber
            self.setCount = setCount
            self.plan = plan
            self.supersetNext = supersetNext
            self.canComplete = canComplete
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
