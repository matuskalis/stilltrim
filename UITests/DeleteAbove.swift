import XCTest

/// "Delete above" removes only the selected photos the user has scrolled past.
/// Needs `scripts/seed-bulk.sh <UDID> 800 pairs`, so the similar list is long enough to scroll. It deletes
/// photos, so add more pairs before running it again.
final class DeleteAbove: SimulatorOnlyTestCase {
    private let deleteAbove = "delete-above"

    @MainActor
    func testDeletingAboveTakesOnlyWhatWasScrolledPastAndKeepsTheRest() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-autoScan", "-tinyFingerprints", "-openCategory", "similar"]
        app.launch()
        grantPhotoAccessIfAsked(app)
        let scan = app.buttons["Scan photos"]
        if scan.waitForExistence(timeout: 3) { scan.tap() }

        let total = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete '")).firstMatch
        XCTAssertTrue(total.waitForExistence(timeout: 180), "the similar list did not open")
        XCTAssertFalse(app.buttons[deleteAbove].exists, "nothing is above the first photo")
        let selectedBefore = try XCTUnwrap(count(in: total.label))

        // A reviewing pace. A hard flick skips rows without the list ever drawing them, and those are never counted.
        for _ in 0..<4 { app.swipeUp(velocity: .slow) }
        let button = app.buttons[deleteAbove]
        try XCTSkipUnless(button.waitForExistence(timeout: 5), "list too short to scroll: run scripts/seed-bulk.sh <UDID> 800 pairs")
        // Reading the top photo takes a few seconds, so the list has stopped moving before the count is read.
        let watched = try XCTUnwrap(topCell(in: app), "no photo is on screen")
        let above = try XCTUnwrap(count(in: button.label))
        XCTAssertGreaterThan(above, 0)
        XCTAssertLessThan(above, selectedBefore, "the photos below the fold must not be included")

        button.tap()
        confirmSystemDeletion()

        let title = app.staticTexts["deletion-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 120), "the deletion summary did not appear")
        XCTAssertTrue(title.label.hasPrefix("\(above) "), "deleted a different number than the button said: \(title.label)")
        app.buttons["Done"].tap()

        // The list goes back to the photo the user was at. It may sit a little lower afterwards, never higher:
        // higher would mean unreviewed photos slid past unseen.
        let same = app.buttons[watched.id]
        XCTAssertTrue(same.waitForExistence(timeout: 15), "the photo at the top of the screen was deleted or scrolled away")
        XCTAssertGreaterThanOrEqual(same.frame.minY, watched.minY - 24, "the list jumped forward after deleting")
        XCTAssertLessThan(same.frame.minY, watched.minY + 200, "the list jumped back by more than a row")
    }

    /// The photo just below the top bar and the pinned heading.
    @MainActor
    private func topCell(in app: XCUIApplication) -> (id: String, minY: CGFloat)? {
        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cell-'")).allElementsBoundByIndex
        let visible = cells.filter { $0.frame.minY > 200 }.min { $0.frame.minY < $1.frame.minY }
        return visible.map { ($0.identifier, $0.frame.minY) }
    }

    private func count(in label: String) -> Int? {
        label.split(whereSeparator: { !$0.isNumber && $0 != "," }).first.flatMap { Int($0.replacingOccurrences(of: ",", with: "")) }
    }
}
