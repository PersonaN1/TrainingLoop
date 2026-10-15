import Foundation
import Observation
import SwiftUI
import TrainingLoopCore

/// User preferences from the Settings tab (SPEC D20, DESIGN V12), kept in UserDefaults.
@MainActor
@Observable
final class AppSettings {
    enum Theme: String, CaseIterable {
        case system, light, dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    // Workout
    var weightUnit: WeightUnit { didSet { defaults.set(weightUnit.rawValue, forKey: Key.weightUnit) } }
    var defaultRestSeconds: Int { didSet { defaults.set(defaultRestSeconds, forKey: Key.defaultRestSeconds) } }
    var autoStartRest: Bool { didSet { defaults.set(autoStartRest, forKey: Key.autoStartRest) } }

    // Sound and haptics
    /// `nil` is "Off".
    var soundSet: SoundSet? { didSet { defaults.set(soundSet?.rawValue ?? Self.off, forKey: Key.soundSet) } }
    var vibration: Bool { didSet { defaults.set(vibration, forKey: Key.vibration) } }
    var voicePrompts: Bool { didSet { defaults.set(voicePrompts, forKey: Key.voicePrompts) } }
    var ignoreSilentMode: Bool { didSet { defaults.set(ignoreSilentMode, forKey: Key.ignoreSilentMode) } }

    // Display
    var showOnLockScreen: Bool { didSet { defaults.set(showOnLockScreen, forKey: Key.showOnLockScreen) } }
    var keepScreenOn: Bool { didSet { defaults.set(keepScreenOn, forKey: Key.keepScreenOn) } }
    var theme: Theme { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Defaults from SPEC D20.
        defaults.register(defaults: [
            Key.defaultRestSeconds: 90,
            Key.autoStartRest: true,
            Key.soundSet: SoundSet.glass.rawValue,
            Key.vibration: true,
            Key.voicePrompts: false,
            Key.ignoreSilentMode: true,
            Key.showOnLockScreen: true,
            Key.keepScreenOn: true,
        ])
        weightUnit = defaults.string(forKey: Key.weightUnit).flatMap(WeightUnit.init) ?? .kg
        defaultRestSeconds = defaults.integer(forKey: Key.defaultRestSeconds)
        autoStartRest = defaults.bool(forKey: Key.autoStartRest)
        // A set that no longer exists falls back to the default rather than to Off.
        let storedSet = defaults.string(forKey: Key.soundSet)
        soundSet = storedSet == Self.off ? nil : storedSet.flatMap(SoundSet.init) ?? .glass
        vibration = defaults.bool(forKey: Key.vibration)
        voicePrompts = defaults.bool(forKey: Key.voicePrompts)
        ignoreSilentMode = defaults.bool(forKey: Key.ignoreSilentMode)
        showOnLockScreen = defaults.bool(forKey: Key.showOnLockScreen)
        keepScreenOn = defaults.bool(forKey: Key.keepScreenOn)
        theme = defaults.string(forKey: Key.theme).flatMap(Theme.init) ?? .system
    }

    private static let off = "off"

    private enum Key {
        static let weightUnit = "weightUnit"
        static let defaultRestSeconds = "defaultRestSeconds"
        static let autoStartRest = "autoStartRest"
        static let soundSet = "soundSet"
        static let vibration = "vibration"
        static let voicePrompts = "voicePrompts"
        static let ignoreSilentMode = "ignoreSilentMode"
        static let showOnLockScreen = "showOnLockScreen"
        static let keepScreenOn = "keepScreenOn"
        static let theme = "theme"
    }
}
