import XCTest

/// Smoke test (TECH T12): start a workout from an example template, tick a set, finish and save,
/// and find it in History. XCTest: UI automation isn't part of Swift Testing.
final class WorkoutSmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testStartTickFinish() {
        let app = XCUIApplication()
        // An empty in-memory store with the example templates; no rest, sound or lock screen to get in the way.
        app.launchArguments = [
            "-UITesting", "YES",
            "-didSeedExamples", "NO",
            "-autoStartRest", "NO",
            "-soundSet", "off",
            "-showOnLockScreen", "NO",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()

        let start = app.buttons["Start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()

        let markDone = app.buttons["Mark Done"].firstMatch
        XCTAssertTrue(markDone.waitForExistence(timeout: 5))
        markDone.tap()
        XCTAssertTrue(app.buttons["Done"].firstMatch.waitForExistence(timeout: 2))

        app.buttons["Finish"].tap()
        let save = app.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["Full Body"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["No Workouts Yet"].exists)
    }
}
