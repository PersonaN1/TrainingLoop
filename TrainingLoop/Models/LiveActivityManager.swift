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
    /// The state last sent: iOS limits updates, so an unchanged one isn't sent again.
    private var lastState: WorkoutActivityAttributes.ContentState?

    var isRunning: Bool { activityID != nil }

    func start(_ attributes: WorkoutActivityAttributes, state: WorkoutActivityAttributes.ContentState) {
        // Before the request: the new activity must not be in the list that gets ended.
        Self.endExisting()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            activityID = try Activity.request(attributes: attributes, content: Self.content(state)).id
            lastState = state
        } catch {
            // In the background iOS refuses; the app asks again when it is back in front.
            Persistence.logger.info("Live Activity not started: \(String(describing: error), privacy: .public)")
        }
    }

    /// After a launch: takes over the activity left by the previous run when the workout goes on,
    /// and ends the rest.
    func adoptExisting(keep: Bool) {
        let activities = Activity<WorkoutActivityAttributes>.activities
        activityID = keep ? activities.first { Self.isLive($0.activityState) }?.id : nil
        lastState = nil
        Self.end(activities.map(\.id).filter { $0 != activityID })
    }

    /// An activity the system ended (after hours on the lock screen, or Live Activities turned off)
    /// no longer counts, so the next change requests a new one.
    func forgetIfEnded() {
        guard let activityID else { return }
        if let state = Self.activity(activityID)?.activityState, Self.isLive(state) { return }
        self.activityID = nil
        lastState = nil
    }

    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activityID, state != lastState else { return }
        lastState = state
        let content = Self.content(state)
        enqueue { await Self.activity(activityID)?.update(content) }
    }

    func end() {
        guard let activityID else { return }
        self.activityID = nil
        lastState = nil
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
        end(Activity<WorkoutActivityAttributes>.activities.map(\.id))
    }

    private nonisolated static func end(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        Task.detached {
            for id in ids {
                await activity(id)?.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    /// Showing, or showing as stale: either can still be updated.
    private nonisolated static func isLive(_ state: ActivityState) -> Bool {
        state == .active || state == .stale
    }

    private nonisolated static func activity(_ id: String) -> Activity<WorkoutActivityAttributes>? {
        Activity<WorkoutActivityAttributes>.activities.first { $0.id == id }
    }
}
