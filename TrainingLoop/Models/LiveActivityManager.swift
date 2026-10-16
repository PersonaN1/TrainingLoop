import ActivityKit
import Foundation
import TrainingLoopCore

/// Starts, updates and ends the workout Live Activity locally, without push (TECH T8). Adapted from SetLoop.
@MainActor
final class LiveActivityManager {
    /// Only the ID is kept: `Activity` is not Sendable, so each task looks it up off the main actor.
    private var activityID: String?
    /// Updates are delivered one after another, so an older state never lands after a newer one.
    private var lastTask: Task<Void, Never>?

    var isRunning: Bool { activityID != nil }

    func start(_ attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        // Before the request: the new activity must not be in the list that gets ended.
        Self.endExisting()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        activityID = try? Activity.request(attributes: attributes, content: Self.content(state)).id
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activityID else { return }
        let content = Self.content(state)
        enqueue { await Self.activity(activityID)?.update(content) }
    }

    func end() {
        guard let activityID else { return }
        self.activityID = nil
        // Removed at once: a finished workout has nothing left to show.
        enqueue { await Self.activity(activityID)?.end(nil, dismissalPolicy: .immediate) }
    }

    /// Waits until every update and end requested so far is delivered.
    func flush() async {
        await lastTask?.value
    }

    private func enqueue(_ work: @escaping @Sendable () async -> Void) {
        let previous = lastTask
        lastTask = Task.detached {
            await previous?.value
            await work()
        }
    }

    /// A running rest goes stale when it ends: the app may be frozen and miss the change to the set card.
    /// The grace keeps a normal update at the end from flashing the stale look.
    private static func content(_ state: WorkoutActivityAttributes.ContentState) -> ActivityContent<WorkoutActivityAttributes.ContentState> {
        let staleDate = state.rest.flatMap { $0.pausedLeft == nil ? $0.end.addingTimeInterval(2) : nil }
        return .init(state: state, staleDate: staleDate)
    }

    /// Activities outlive the app: a killed or reinstalled app leaves its last one on the lock screen.
    /// The IDs are taken synchronously, so an activity requested after this call survives.
    nonisolated static func endExisting() {
        let ids = Activity<WorkoutActivityAttributes>.activities.map(\.id)
        guard !ids.isEmpty else { return }
        Task.detached {
            for id in ids {
                await activity(id)?.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private nonisolated static func activity(_ id: String) -> Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first { $0.id == id }
    }
}
