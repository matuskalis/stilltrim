import XCTest

/// Needs the seeded simulator library (scripts/seed-simulator.sh). It deletes the three seeded
/// screenshots, so reseed before running it again.
final class CleanupFlow: SimulatorOnlyTestCase {
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

        let sectionSelect = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'select-'")).firstMatch
        XCTAssertTrue(sectionSelect.waitForExistence(timeout: 5), "the screenshots have no heading with a select button")
        sectionSelect.tap()
        XCTAssertFalse(app.buttons["Select items to delete"].exists, "the heading did not select its screenshots")
        sectionSelect.tap()
        XCTAssertTrue(app.buttons["Select items to delete"].waitForExistence(timeout: 5), "the heading did not deselect them")

        app.buttons["Select all"].tap()
        let delete = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()

        confirmSystemDeletion()

        XCTAssertTrue(app.staticTexts["3 deleted"].waitForExistence(timeout: 20))
    }
}
