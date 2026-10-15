import SwiftUI

/// Tabs: Workouts · History · Exercises · Settings (SPEC D13).
struct RootView: View {
    var body: some View {
        TabView {
            PlaceholderTab(title: "Workouts", systemImage: "figure.strengthtraining.traditional")
                .tabItem { Label("Workouts", systemImage: "figure.strengthtraining.traditional") }
            PlaceholderTab(title: "History", systemImage: "clock.arrow.circlepath",
                           hint: "Start a workout — it will appear here")
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            PlaceholderTab(title: "Exercises", systemImage: "dumbbell")
                .tabItem { Label("Exercises", systemImage: "dumbbell") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// An empty tab until its screen is built.
private struct PlaceholderTab: View {
    let title: LocalizedStringKey
    let systemImage: String
    var hint: LocalizedStringKey?

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                if let hint { Text(hint) }
            }
            .navigationTitle(title)
        }
    }
}

#Preview {
    RootView()
}
