import XCTest

/// A finger swipe across photos selects them, and a second swipe across the same photos deselects them.
/// It deletes nothing, but needs the seeded library (`scripts/seed-simulator.sh <UDID>`) for Blurry and dark.
final class DragSelect: SimulatorOnlyTestCase {
    @MainActor
    func testSwipingAcrossTheFirstThreePhotosSelectsThenDeselectsThem() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-autoScan", "-tinyFingerprints", "-openCategory", "lowQuality"]
        app.launch()
        grantPhotoAccessIfAsked(app)
        let scan = app.buttons["Scan photos"]
        if scan.waitForExistence(timeout: 3) { scan.tap() }

        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cell-'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 180), "the Blurry and dark list did not open")

        let all = cells.allElementsBoundByIndex.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        let firstRowTop = try XCTUnwrap(all.first).frame.minY
        let firstRow = all.filter { $0.frame.minY == firstRowTop }
        try XCTSkipIf(firstRow.count < 3, "the first row has fewer than three photos")
        let swiped = Array(firstRow.prefix(3))
        let swipedIDs = Set(swiped.map(\.identifier))

        // A short press, so the swipe starts as a swipe and not as a touch-and-hold that opens the menu.
        swiped[0].press(forDuration: 0.1, thenDragTo: swiped[2])
        XCTAssertEqual(selectedIDs(in: cells), swipedIDs, "the swipe did not select exactly the three photos it crossed")

        swiped[0].press(forDuration: 0.1, thenDragTo: swiped[2])
        XCTAssertTrue(selectedIDs(in: cells).isDisjoint(with: swipedIDs), "the second swipe did not deselect them")
    }

    @MainActor
    private func selectedIDs(in cells: XCUIElementQuery) -> Set<String> {
        Set(cells.allElementsBoundByIndex.filter { ($0.value as? String) == "Selected" }.map(\.identifier))
    }
}
