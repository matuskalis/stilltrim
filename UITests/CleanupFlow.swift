import XCTest

/// Needs the seeded simulator library (scripts/seed-simulator.sh). It deletes the three seeded
/// screenshots, so reseed before running it again.
final class CleanupFlow: XCTestCase {
    @MainActor
    func testDeleteScreenshotsThroughTheSystemPrompt() {
        let app = XCUIApplication()
        app.launchArguments = ["-autoScan", "-tinyFingerprints"]
        app.launch()
        grantPhotoAccessIfAsked(app)
        let scan = app.buttons["Scan photos"]
        if scan.waitForExistence(timeout: 3) { scan.tap() }

        let row = app.staticTexts["Screenshots"]
        XCTAssertTrue(row.waitForExistence(timeout: 120), "scan did not finish")
        row.tap()

        app.buttons["Select all"].tap()
        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "iOS did not show its own delete confirmation")
        alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["3 deleted"].waitForExistence(timeout: 20))
    }
}
