import ActivityKit
import SwiftUI
import TrainingLoopCore
import WidgetKit

/// Lock screen and Dynamic Island (DESIGN V11). A stub: the rest and set cards come with the workout screen.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.workoutName).font(.headline)
                Text(context.state.exerciseName).font(.subheadline)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.exerciseName)
                }
            } compactLeading: {
                Image(systemName: "dumbbell")
            } compactTrailing: {
                Text(context.state.exerciseName).lineLimit(1).frame(maxWidth: 52)
            } minimal: {
                Image(systemName: "dumbbell")
            }
        }
    }
}
