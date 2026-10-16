import AppIntents

/// Lock Screen and Dynamic Island buttons (DESIGN V11, TECH T8).
///
/// Compiled into the app and the widget: the widget only shows the buttons, while iOS runs
/// `perform()` in the app's process, where `WorkoutCommands.handler` reaches the running workout.
enum WorkoutCommand: Sendable {
    /// "Done": ticks the next set with the shown values and starts the rest (D7).
    case completeSet
    case addRest
    case skipRest
}

@MainActor
enum WorkoutCommands {
    /// Set by the workout controller; nil in the widget and when no workout runs.
    static var handler: ((WorkoutCommand) -> Void)?
    /// Waits for the Live Activity to show the command's result: the app may be suspended right after `perform()`.
    static var flush: (@MainActor () async -> Void)?

    static func run(_ command: WorkoutCommand) async {
        handler?(command)
        await flush?()
    }
}

struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark Set Done"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutCommands.run(.completeSet)
        return .result()
    }
}

struct AddRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 10 Seconds of Rest"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutCommands.run(.addRest)
        return .result()
    }
}

struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip Rest"
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await WorkoutCommands.run(.skipRest)
        return .result()
    }
}
