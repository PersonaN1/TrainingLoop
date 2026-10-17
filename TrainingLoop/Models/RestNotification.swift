import Foundation
import UserNotifications

/// A notification at the end of a rest, for when the app can't signal it itself (SPEC D5).
///
/// The app stays awake on the lock screen only while it holds the playback audio session, that is with
/// a sound or the voice on and "Ignore Silent Mode" on (TECH T6). Otherwise iOS freezes it in the
/// background and the end of a rest would pass unnoticed; the notification signals it instead.
/// In the app the rest panel and the app's own signals show it, so the notification isn't presented there.
@MainActor
final class RestNotification: NSObject, UNUserNotificationCenterDelegate {
    private let settings: AppSettings
    private let center = UNUserNotificationCenter.current()
    private static let id = "rest-end"
    /// Bumped on every cancel, so a request still waiting for permission isn't added after it.
    private var generation = 0

    init(settings: AppSettings) {
        self.settings = settings
        super.init()
        center.delegate = self
    }

    /// Whether the app plays the end of a rest itself, even on the lock screen.
    private var appSignals: Bool {
        (settings.soundSet != nil || settings.voicePrompts) && settings.ignoreSilentMode
    }

    /// A rest runs until `endsAt`; replaces an earlier one.
    func schedule(at endsAt: Date, next: String?) {
        cancel()
        guard !appSignals else { return }
        let sound: UNNotificationSound? =
            settings.soundSet != nil || settings.voicePrompts || settings.vibration ? .default : nil
        let center = center
        let generation = generation
        Task {
            // Asked at the first rest that needs it, when the reason is plain.
            let status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            } else if status != .authorized && status != .provisional && status != .ephemeral {
                return
            }
            // The rest may have been skipped while the question was showing; the time left is taken now.
            let interval = endsAt.timeIntervalSinceNow
            guard generation == self.generation, interval > 1 else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Rest is over")
            if let next { content.body = next }
            // The standard sound follows the ringer switch: in silent mode it only vibrates.
            content.sound = sound
            let request = UNNotificationRequest(
                identifier: Self.id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
            try? await center.add(request)
        }
    }

    /// The rest was skipped, changed or paused, or the workout ended.
    func cancel() {
        generation += 1
        center.removePendingNotificationRequests(withIdentifiers: [Self.id])
    }

    /// Back in the app: a delivered notification has done its job.
    func clearDelivered() {
        center.removeDeliveredNotifications(withIdentifiers: [Self.id])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        []
    }
}
