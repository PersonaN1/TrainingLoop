import Foundation
import SwiftUI
import TipKit

// First-run hints (SPEC D25, DESIGN V15), as in SetLoop: each shows once and goes away after ×
// or after the action it talks about. Only the split-set hint shows during a workout.

/// Top of the Workouts tab: what the example templates do.
struct TemplatesIntroTip: Tip {
    var id: String { TipsSetup.id("templatesIntro") }
    var title: Text { Text("Start with an example") }
    var message: Text? {
        Text("▶ starts a workout right away, + makes your own template. Tap a template to see its exercises.")
    }
    var image: Image? { Image(systemName: "hand.tap") }
}

/// Swipe and long press on a template are invisible otherwise; shown after a template has been opened.
struct TemplateActionsTip: Tip {
    @Parameter static var introDone: Bool = false
    @Parameter static var openedTemplate: Bool = false

    var id: String { TipsSetup.id("templateActions") }
    var title: Text { Text("More actions") }
    var message: Text? {
        Text("Swipe a template left to edit, duplicate or delete it. Or touch and hold it.")
    }
    var image: Image? { Image(systemName: "hand.draw") }
    var rules: [Rule] {
        #Rule(Self.$introDone) { $0 }
        #Rule(Self.$openedTemplate) { $0 }
    }
}

/// On the template preview's Start button.
struct StartTip: Tip {
    var id: String { TipsSetup.id("start") }
    var title: Text { Text("Start the workout") }
    var message: Text? {
        Text("Tick each set: the rest timer starts by itself and keeps running on the Lock Screen.")
    }
}

/// During a workout, under the first unfinished exercise of both sides (SPEC D23).
struct SplitSetTip: Tip {
    var id: String { TipsSetup.id("splitSet") }
    var title: Text { Text("Sides differed?") }
    var message: Text? { Text("Hold the set or swipe it right → “Split into L and R”.") }
    var image: Image? { Image(systemName: "arrow.left.and.right") }
}

/// On the summary of the first workout.
struct HistoryTip: Tip {
    var id: String { TipsSetup.id("history") }
    var title: Text { Text("Keep it in History") }
    var message: Text? {
        Text("Save, and the workout appears in History. New records are marked with 🏆.")
    }
    var image: Image? { Image(systemName: "clock.arrow.circlepath") }
}

/// Top of History: workouts go out as text.
struct ShareHistoryTip: Tip {
    var id: String { TipsSetup.id("shareHistory") }
    var title: Text { Text("Share as text") }
    var message: Text? {
        Text("↑ shares the workouts of a period, Select — the ones you tick. For a coach, a chat or your notes.")
    }
    var image: Image? { Image(systemName: "square.and.arrow.up") }
}

/// Top of the Exercises tab: every exercise has its statistics.
struct ExerciseStatsTip: Tip {
    var id: String { TipsSetup.id("exerciseStats") }
    var title: Text { Text("Progress of an exercise") }
    var message: Text? {
        Text("Tap an exercise to see its chart, records and best weight for reps.")
    }
    var image: Image? { Image(systemName: "chart.xyaxis.line") }
}

/// On Exercises → Select, after the statistics tip.
struct MergeExercisesTip: Tip {
    @Parameter static var statsTipDone: Bool = false

    var id: String { TipsSetup.id("mergeExercises") }
    var title: Text { Text("Two of the same?") }
    var message: Text? {
        Text("Select two copies of one exercise and merge them, history included.")
    }
    var rules: [Rule] {
        #Rule(Self.$statsTipDone) { $0 }
    }
}

@MainActor
enum TipsSetup {
    nonisolated static let generationKey = "tipsGeneration"

    /// Bumped by "Show Tips Again": tips with a new ID start unseen. TipKit's own reset works
    /// only before `Tips.configure`, which would mean restarting the app.
    static var generation: Int { UserDefaults.standard.integer(forKey: generationKey) }

    nonisolated static func id(_ name: String) -> String {
        "\(name).\(UserDefaults.standard.integer(forKey: generationKey))"
    }

    static func configure() {
        let arguments = ProcessInfo.processInfo.arguments
        // App Store screenshots and UI checks: -hideTips / -showAllTips.
        if arguments.contains("-hideTips") { Tips.hideAllTipsForTesting() }
        if arguments.contains("-showAllTips") { Tips.showAllTipsForTesting() }
        #if DEBUG
        if TestLaunch.isTesting { Tips.hideAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    /// Settings → Show Tips Again.
    static func showAgain() {
        UserDefaults.standard.set(generation + 1, forKey: generationKey)
        TemplateActionsTip.introDone = false
        TemplateActionsTip.openedTemplate = false
        MergeExercisesTip.statsTipDone = false
    }
}

extension View {
    /// Runs `action` once `tip` is closed or its action is done, to show the next tip in a chain.
    func onTipInvalidated(_ tip: some Tip, perform action: @escaping @MainActor () -> Void) -> some View {
        task(id: tip.id) {
            for await status in tip.statusUpdates {
                if case .invalidated = status {
                    action()
                    return
                }
            }
        }
    }

    /// A tip card in a list: no row background, as in SetLoop (DESIGN V15).
    func tipRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
    }
}
