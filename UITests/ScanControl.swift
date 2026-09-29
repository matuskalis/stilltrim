import XCTest

/// Cancelling a scan, and erasing app data in the middle of one, must both end cleanly.
/// Needs a library big enough for a scan to last a few seconds: run scripts/seed-bulk.sh first.
/// Skipped when the scan finishes too quickly to interrupt.
final class ScanControl: SimulatorOnlyTestCase {
    @MainActor
    private func launchAndErase() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-tinyFingerprints"]
        app.launch()
        grantPhotoAccessIfAsked(app)
        eraseAppData(app)
        return app
    }

    @MainActor
    private func eraseAppData(_ app: XCUIApplication) {
        app.buttons["Settings"].tap()
        app.buttons["Erase app data"].tap()
        app.buttons["Erase"].tap()
        app.buttons["Done"].tap()
    }

    @MainActor
    private func startScanOrSkip(_ app: XCUIApplication) throws {
        let scan = app.buttons["Scan photos"]
        XCTAssertTrue(scan.waitForExistence(timeout: 30))
        scan.tap()
        try XCTSkipUnless(app.buttons["Cancel"].waitForExistence(timeout: 5), "library too small to interrupt: run scripts/seed-bulk.sh")
    }

    @MainActor
    func testCancelStopsTheScanAndAnotherCanStart() throws {
        let app = launchAndErase()
        try startScanOrSkip(app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Scan photos"].waitForExistence(timeout: 20), "cancelling did not return to the start")
        app.buttons["Scan photos"].tap()
        XCTAssertTrue(app.staticTexts["Screenshots"].waitForExistence(timeout: 180), "the second scan did not finish")
    }

    @MainActor
    func testErasingInTheMiddleOfAScanLeavesNoResultsAndAllowsANewScan() throws {
        let app = launchAndErase()
        try startScanOrSkip(app)
        eraseAppData(app)
        XCTAssertTrue(app.buttons["Scan photos"].waitForExistence(timeout: 30), "erase did not return to the start")
        XCTAssertFalse(app.staticTexts["Screenshots"].exists, "erased results came back")
        app.buttons["Scan photos"].tap()
        XCTAssertTrue(app.staticTexts["Screenshots"].waitForExistence(timeout: 180), "the scan after erasing did not finish")
    }
}
