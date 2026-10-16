import ActivityKit
import SwiftUI
import TrainingLoopCore
import WidgetKit

/// Lock screen and Dynamic Island (DESIGN V11): the green rest card or the sea-blue set card.
/// The countdown runs in the system, without the app.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state, attributes: context.attributes, isStale: context.isStale)
                .activityBackgroundTint(context.state.isResting ? .rest : .set)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            // On the black island the colors are lightened to read (as SetLoop V10).
            let accent: Color = state.isResting ? .restLight : .setLight
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(state.isResting ? String(localized: "Rest") : state.exerciseName ?? "")
                        .font(.headline)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let rest = state.rest {
                        CountdownText(rest: rest).font(.system(.title, design: .rounded, weight: .bold))
                    } else {
                        Text(state.plan).font(.system(.title3, design: .rounded, weight: .bold)).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(state.isResting ? state.nextText : state.positionText)
                            .font(.footnote)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        ActivityButtons(state: state, tint: accent, label: .black)
                    }
                }
            } compactLeading: {
                if let rest = state.rest {
                    RestRing(rest: rest, tint: accent).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(accent)
                }
            } compactTrailing: {
                Group {
                    if let rest = state.rest {
                        CountdownText(rest: rest).frame(maxWidth: 52)
                    } else {
                        // "Squat 2/4".
                        Text(state.compactSet).lineLimit(1).frame(maxWidth: 110)
                    }
                }
                .font(.system(.body, design: .rounded, weight: .bold))
                .foregroundStyle(accent)
            } minimal: {
                if let rest = state.rest {
                    RestRing(rest: rest, tint: accent).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "dumbbell.fill").foregroundStyle(accent)
                }
            }
        }
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    let attributes: WorkoutActivityAttributes
    /// The rest ended, but the app hasn't updated the activity: it is frozen in the background.
    let isStale: Bool

    var body: some View {
        // The lock screen card is limited to ~160 pt.
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "TrainingLoop · \(attributes.workoutName)").lineLimit(1)
                Spacer()
                // "1:05:12": the `.timer` style spells out hours ("1 hour 5…").
                Text(timerInterval: attributes.startedAt...Date.distantFuture, countsDown: false)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
            .font(.footnote)
            .opacity(0.85)
            if let rest = state.rest {
                restCard(rest)
            } else {
                setCard
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    @ViewBuilder
    private func restCard(_ rest: WorkoutActivityAttributes.ContentState.Rest) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rest.pausedLeft == nil ? "Rest" : "Rest · Paused").font(.headline)
                Text(isStale ? String(localized: "Open TrainingLoop to continue") : state.nextText)
                    .font(.footnote)
                    .lineLimit(2)
                    .opacity(0.9)
            }
            Spacer(minLength: 8)
            CountdownText(rest: rest)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .lineLimit(1)
                .frame(maxWidth: 130, alignment: .trailing)
        }
        HStack(spacing: 12) {
            RestBar(rest: rest)
            Spacer(minLength: 0)
            ActivityButtons(state: state, tint: .white, label: .rest)
        }
    }

    @ViewBuilder
    private var setCard: some View {
        if state.exerciseName != nil {
            Text(state.positionText).font(.headline).lineLimit(1)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.plan.isEmpty ? " " : state.plan)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if let next = state.supersetNext {
                        Text(next).font(.footnote).lineLimit(1).opacity(0.9)
                    }
                }
                Spacer(minLength: 8)
                ActivityButtons(state: state, tint: .white, label: .set)
            }
        } else {
            Text("All sets are done").font(.headline)
            Text("Open TrainingLoop to finish").font(.footnote).opacity(0.9)
        }
    }
}

/// "+10" and "Skip" during a rest, "Done" on a set; the app performs them (TECH T8).
private struct ActivityButtons: View {
    let state: WorkoutActivityAttributes.ContentState
    let tint: Color
    /// Text on the filled "Done".
    let label: Color

    var body: some View {
        if state.isResting {
            HStack(spacing: 8) {
                Button(intent: AddRestIntent()) { capsule(Text(verbatim: "+10")) }
                    .accessibilityLabel("Plus 10 seconds")
                Button(intent: SkipRestIntent()) { capsule(Text("Skip")) }
            }
            .buttonStyle(.plain)
        } else if state.canComplete {
            // No icon, so it fits (DESIGN V11).
            Button(intent: CompleteSetIntent()) {
                Text("Done")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(label)
                    .padding(.horizontal, 20)
                    .frame(height: 40)
                    .background(tint, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private func capsule(_ text: Text) -> some View {
        text
            .font(.system(size: 15, weight: .bold))
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(tint.opacity(0.22), in: Capsule())
    }
}

private struct CountdownText: View {
    let rest: WorkoutActivityAttributes.ContentState.Rest

    var body: some View {
        Group {
            if let left = rest.pausedLeft {
                let seconds = Int(left.rounded(.up))
                Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
            } else {
                Text(timerInterval: rest.start...max(rest.start, rest.end), countsDown: true)
            }
        }
        .monospacedDigit()
        .multilineTextAlignment(.trailing)
    }
}

private struct RestBar: View {
    let rest: WorkoutActivityAttributes.ContentState.Rest

    var body: some View {
        if rest.pausedLeft == nil {
            ProgressView(timerInterval: rest.start...max(rest.start, rest.end), countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(.white)
        }
    }
}

private struct RestRing: View {
    let rest: WorkoutActivityAttributes.ContentState.Rest
    let tint: Color

    var body: some View {
        if rest.pausedLeft == nil {
            ProgressView(timerInterval: rest.start...max(rest.start, rest.end), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(tint)
        } else {
            Image(systemName: "pause.fill").foregroundStyle(tint)
        }
    }
}

private extension WorkoutActivityAttributes.ContentState {
    /// "Squat · set 2 of 4".
    var positionText: String {
        guard let exerciseName else { return String(localized: "All sets are done") }
        return String(localized: "\(exerciseName) · set \(setNumber) of \(setCount)")
    }

    /// "Next: Squat, set 2 · 60 kg × 8".
    var nextText: String {
        guard let exerciseName else { return String(localized: "All sets are done") }
        let next = String(localized: "Next: \(exerciseName), set \(setNumber)")
        return plan.isEmpty ? next : "\(next) · \(plan)"
    }

    /// "Squat 2/4".
    var compactSet: String {
        guard let exerciseName else { return "✓" }
        return "\(exerciseName) \(setNumber)/\(setCount)"
    }
}

private extension Color {
    /// Rest green and set sea blue (DESIGN V1, V11), and their lighter versions for the black island.
    static let rest = Color(red: 0x1E / 255, green: 0x8E / 255, blue: 0x52 / 255)
    static let set = Color(red: 0x0E / 255, green: 0x7C / 255, blue: 0x9E / 255)
    static let restLight = Color(red: 0x4C / 255, green: 0xD3 / 255, blue: 0x8A / 255)
    static let setLight = Color(red: 0x4F / 255, green: 0xC3 / 255, blue: 0xE6 / 255)
}
