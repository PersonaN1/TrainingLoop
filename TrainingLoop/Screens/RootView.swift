import SwiftUI

/// Tabs: Workouts · History · Exercises · Settings (SPEC D13). A running workout opens over them and,
/// when collapsed, stays as a bar above the tabs.
struct RootView: View {
    @Environment(WorkoutController.self) private var workouts
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var workouts = workouts
        TabView {
            TemplateListView()
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "dumbbell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .runningWorkoutBar(isShown: workouts.workout != nil && !workouts.isPresented) {
            RunningWorkoutBar()
        }
        .fullScreenCover(isPresented: $workouts.isPresented) {
            WorkoutView()
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            workouts.appDidBecomeActive()
            workouts.checkForgotten()
        }
        // The lock screen follows Settings at once, not at the next tick.
        .onChange(of: settings.showOnLockScreen) { workouts.refreshActivity() }
        .onChange(of: settings.weightUnit) { workouts.refreshActivity() }
        // "Keep Screen On" holds only while a workout runs (D20).
        .onChange(of: workouts.workout != nil && settings.keepScreenOn, initial: true) { _, keepOn in
            UIApplication.shared.isIdleTimerDisabled = keepOn
        }
        .forgottenWorkoutAlert(whileOpen: false)
    }
}

extension View {
    /// "Is the workout still going?" (D19), from the root while the workout is collapsed and from the
    /// workout screen while it is open: an alert of a view under a full-screen cover never shows.
    func forgottenWorkoutAlert(whileOpen: Bool) -> some View {
        modifier(ForgottenWorkoutAlert(whileOpen: whileOpen))
    }
}

private struct ForgottenWorkoutAlert: ViewModifier {
    @Environment(WorkoutController.self) private var workouts
    let whileOpen: Bool

    func body(content: Content) -> some View {
        content.alert("Is the workout still going?",
                      isPresented: Binding(get: { workouts.asksIfForgotten && workouts.isPresented == whileOpen },
                                           set: { if !$0 { workouts.asksIfForgotten = false } })) {
            Button("Continue") { workouts.keepGoing() }
            if (workouts.workout?.doneSetCount ?? 0) > 0 {
                Button("Finish") { workouts.finishForgotten() }
            } else {
                // Nothing to save, so no summary.
                Button("Discard Workout", role: .destructive) { workouts.discard() }
            }
        } message: {
            Text("No sets have been marked for over two hours.")
        }
    }
}

/// The collapsed workout: name, time and the next set or the rest; a tap opens it.
private struct RunningWorkoutBar: View {
    @Environment(WorkoutController.self) private var workouts

    var body: some View {
        if let workout = workouts.workout {
            Button {
                workouts.isPresented = true
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workout.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(workout.startedAt, style: .timer)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Spacer()
                    if let rest = workouts.rest {
                        Label {
                            if rest.isPaused {
                                Text(RestFormat.time(rest.left(at: .now))).monospacedDigit()
                            } else {
                                Text(timerInterval: Date.now...max(rest.endsAt, .now), countsDown: true)
                                    .monospacedDigit()
                            }
                        } icon: {
                            Image(systemName: rest.isPaused ? "pause.fill" : "timer")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rest)
                    }
                    Image(systemName: "chevron.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                // The whole capsule opens the workout, not just its text.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }
}

private extension View {
    /// iOS 26.1+ has a place for it in the tab bar; earlier systems get a bar on top of it.
    @ViewBuilder
    func runningWorkoutBar(isShown: Bool, @ViewBuilder content: () -> some View) -> some View {
        if #available(iOS 26.1, *) {
            // Toggled, not added and removed: that would rebuild the tabs and lose the selected one.
            tabViewBottomAccessory(isEnabled: isShown) { content() }
        } else {
            safeAreaInset(edge: .bottom, spacing: 0) {
                if isShown {
                    content()
                        .padding(.vertical, 10)
                        .background(.bar)
                        .padding(.bottom, 49)
                }
            }
        }
    }
}

extension Color {
    /// Rest is green in both apps (DESIGN V1).
    static let rest = Color(red: 0x1E / 255, green: 0x8E / 255, blue: 0x52 / 255)
    /// Coral means a record (DESIGN V7): this for icons and 🏆, `recordText` for text on white.
    static let record = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x52 / 255)
    /// Dark coral keeps ~4.5:1 on white; on a dark background the bright one reads better.
    static let recordText = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0xFF / 255, green: 0x6B / 255, blue: 0x52 / 255, alpha: 1)
            : UIColor(red: 0xD2 / 255, green: 0x45 / 255, blue: 0x2E / 255, alpha: 1)
    })
}

#Preview {
    RootView()
        .environment(AppSettings())
        .environment(WorkoutController(settings: AppSettings()))
        .modelContainer(for: Exercise.self, inMemory: true)
}
