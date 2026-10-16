import SwiftUI

/// Tabs: Workouts · History · Exercises · Settings (SPEC D13). A running workout opens over them and,
/// when collapsed, stays as a bar above the tabs.
struct RootView: View {
    @Environment(WorkoutController.self) private var workouts
    @Environment(\.scenePhase) private var scenePhase
    @State private var askingIfForgotten = false

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
            if phase == .active, workouts.isForgotten { askingIfForgotten = true }
        }
        .alert("Is the workout still going?", isPresented: $askingIfForgotten) {
            Button("Continue") { workouts.isPresented = true }
            Button("Finish") { workouts.finishForgotten() }
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
                            Text(timerInterval: Date.now...max(rest.endsAt, .now), countsDown: true)
                                .monospacedDigit()
                        } icon: {
                            Image(systemName: "timer")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.rest)
                    }
                    Image(systemName: "chevron.up")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
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
}

#Preview {
    RootView()
        .environment(AppSettings())
        .environment(WorkoutController(settings: AppSettings()))
        .modelContainer(for: Exercise.self, inMemory: true)
}
