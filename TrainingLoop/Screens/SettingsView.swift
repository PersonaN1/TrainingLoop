import SwiftData
import SwiftUI
import TrainingLoopCore

/// Groups: Workout / Sound and Haptics / Display / Exercises / About (SPEC D20, DESIGN V12).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<Exercise> { $0.isHidden && $0.builtinKey != nil })
    private var hidden: [Exercise]
    @Query(filter: #Predicate<Exercise> { $0.isArchived && $0.builtinKey == nil })
    private var archived: [Exercise]

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section("Workout") {
                    Picker("Units", selection: $settings.weightUnit) {
                        ForEach(WeightUnit.allCases, id: \.self) { unit in
                            Text(unit.title).tag(unit)
                        }
                    }
                    Picker("Default Rest", selection: $settings.defaultRestSeconds) {
                        ForEach(Self.restChoices(including: settings.defaultRestSeconds), id: \.self) { seconds in
                            Text(Duration.seconds(seconds).formatted(.time(pattern: .minuteSecond))).tag(seconds)
                        }
                    }
                    Toggle("Start Rest After a Set", isOn: $settings.autoStartRest)
                }

                Section {
                    Picker("Sounds", selection: $settings.soundSet) {
                        Text("Off").tag(SoundSet?.none)
                        ForEach(SoundSet.allCases, id: \.self) { set in
                            Text(set.title).tag(SoundSet?.some(set))
                        }
                    }
                    Toggle("Vibration", isOn: $settings.vibration)
                    Toggle("Voice Prompts", isOn: $settings.voicePrompts)
                    Toggle("Ignore Silent Mode", isOn: $settings.ignoreSilentMode)
                } header: {
                    Text("Sound and Haptics")
                } footer: {
                    // SPEC D20: rest is real time; iOS silences the app during a call.
                    Text("Signals don't play during a call.")
                }

                Section("Display") {
                    Toggle("Show on Lock Screen", isOn: $settings.showOnLockScreen)
                    Toggle("Keep Screen On", isOn: $settings.keepScreenOn)
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppSettings.Theme.allCases, id: \.self) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                }

                Section("Exercises") {
                    NavigationLink {
                        HiddenExercisesView()
                    } label: {
                        LabeledContent("Hidden Exercises", value: hidden.count.formatted())
                    }
                    NavigationLink {
                        ArchivedExercisesView()
                    } label: {
                        LabeledContent("Archive", value: archived.count.formatted())
                    }
                }

                Section("About") {
                    Link("Privacy Policy", destination: SupportLinks.privacy)
                    Link("Support", destination: SupportLinks.support)
                    LabeledContent("Version", value: Bundle.main.versionString)
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// 0:30 to 5:00; a stored value outside the list stays selectable.
    static func restChoices(including current: Int) -> [Int] {
        let choices = [30, 45, 60, 75, 90, 120, 150, 180, 240, 300]
        return choices.contains(current) ? choices : (choices + [current]).sorted()
    }
}

/// Built-in exercises hidden from the catalog (SPEC D8); unhiding returns them.
private struct HiddenExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isHidden && $0.builtinKey != nil })
    private var exercises: [Exercise]

    var body: some View {
        ExerciseRestoreList(exercises: exercises, emptyText: "No hidden exercises", actionTitle: "Show") { exercise in
            exercise.isHidden = false
            context.saveOrReport()
        }
        .navigationTitle("Hidden Exercises")
    }
}

/// Custom exercises deleted after they reached the history (SPEC D8); restoring returns them to the catalog.
private struct ArchivedExercisesView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Exercise> { $0.isArchived && $0.builtinKey == nil })
    private var exercises: [Exercise]

    var body: some View {
        ExerciseRestoreList(exercises: exercises, emptyText: "The archive is empty", actionTitle: "Restore") { exercise in
            exercise.isArchived = false
            context.saveOrReport()
        }
        .navigationTitle("Archive")
    }
}

private struct ExerciseRestoreList: View {
    let exercises: [Exercise]
    let emptyText: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    let restore: (Exercise) -> Void

    var body: some View {
        let sorted = exercises.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        List(sorted) { exercise in
            HStack {
                Text(exercise.name)
                Spacer()
                Button(actionTitle) { restore(exercise) }
                    .buttonStyle(.borderless)
            }
        }
        .overlay {
            if exercises.isEmpty {
                ContentUnavailableView(emptyText, systemImage: "tray")
            }
        }
    }
}

/// Pages in the project's GitHub Pages site (TECH T9).
enum SupportLinks {
    static let privacy = URL(string: "https://personan1.github.io/TrainingLoop/privacy/")!
    static let support = URL(string: "https://personan1.github.io/TrainingLoop/support/")!
}

extension WeightUnit {
    var title: String {
        switch self {
        case .kg: String(localized: "Kilograms")
        case .lb: String(localized: "Pounds")
        }
    }
}

extension SoundSet {
    var title: String {
        switch self {
        case .glass: String(localized: "Glass")
        case .marimba: String(localized: "Marimba")
        case .note: String(localized: "sound.note", defaultValue: "Note")
        }
    }
}

extension AppSettings.Theme {
    var title: String {
        switch self {
        case .system: String(localized: "System")
        case .light: String(localized: "Light")
        case .dark: String(localized: "Dark")
        }
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
        .environment(WorkoutController(settings: AppSettings()))
        .modelContainer(for: Exercise.self, inMemory: true)
}
