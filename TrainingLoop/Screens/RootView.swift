import SwiftUI

/// Tabs: Workouts · History · Exercises · Settings (SPEC D13).
struct RootView: View {
    var body: some View {
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
    }
}

#Preview {
    RootView()
        .environment(AppSettings())
        .modelContainer(for: Exercise.self, inMemory: true)
}
