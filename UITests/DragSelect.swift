import XCTest

/// A finger swipe across photos selects them, a second swipe across the same photos deselects them, a swipe inside
/// one photo selects it once, a tap still toggles one photo and a vertical swipe still scrolls without selecting.
/// It deletes nothing, but needs the seeded library (`scripts/seed-simulator.sh <UDID>`) for Blurry and dark.
final class DragSelect: SimulatorOnlyTestCase {
    @MainActor
    func testSwipingAcrossTheFirstThreePhotosSelectsThenDeselectsThem() throws {
        let cells = openBlurryAndDark().cells

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

        let below = try XCTUnwrap(all.first { $0.frame.minY > firstRowTop })
        below.tap()
        XCTAssertEqual(selectedIDs(in: cells), [below.identifier], "a plain tap no longer toggles exactly one photo")
    }

    @MainActor
    func testSwipingInsideOnePhotoSelectsItOnce() throws {
        let cells = openBlurryAndDark().cells
        let all = cells.allElementsBoundByIndex.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        let firstRow = all.filter { $0.frame.minY == all.first?.frame.minY }
        // Not the first column: a touch that starts at the screen edge belongs to the system back swipe.
        try XCTSkipIf(firstRow.count < 2, "the first row has a single photo")
        let cell = firstRow[1]
        let id = cell.identifier
        let start = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
        let end = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))

        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertEqual(selectedIDs(in: cells), [id], "a swipe inside one photo did not select it exactly once")
    }

    /// Like the Photos app: a finger that drags a selection to the bottom edge scrolls the list on and keeps selecting.
    @MainActor
    func testDraggingASelectionToTheBottomEdgeScrollsTheList() throws {
        let (app, cells) = openBlurryAndDark()
        let lowestBottom = cells.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        try XCTSkipIf(lowestBottom <= app.frame.height, "the list fits on one screen")
        let all = cells.allElementsBoundByIndex.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        let first = try XCTUnwrap(all.first)
        let firstID = first.identifier
        let startY = first.frame.minY
        // The first photo of the lowest row whose middle is on screen, dragged across and down into the bottom edge zone.
        // The drag must be more across than down, or the list takes it as a scroll, and it ends over the second column,
        // which every row has.
        let lowestRowTop = try XCTUnwrap(all.filter { $0.frame.midY < app.frame.height - 100 }.last).frame.minY
        let start = try XCTUnwrap(all.first { $0.frame.minY == lowestRowTop })
        let from = start.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.96))

        from.press(forDuration: 0.1, thenDragTo: edge, withVelocity: .default, thenHoldForDuration: 2)

        let moved = app.buttons[firstID]
        XCTAssertTrue(!moved.exists || moved.frame.minY < startY - 100, "the list did not scroll while the finger sat at the bottom edge")
        XCTAssertGreaterThan(selectedIDs(in: cells).count, 3, "the selection did not follow the list as it scrolled")
    }

    /// The measured failure this guards: a SwiftUI drag gesture on the grid stopped the list scrolling.
    @MainActor
    func testVerticalSwipesStillScrollAndSelectNothing() throws {
        let (app, cells) = openBlurryAndDark()
        let lowestBottom = cells.allElementsBoundByIndex.map(\.frame.maxY).max() ?? 0
        try XCTSkipIf(lowestBottom <= app.frame.height, "the list fits on one screen")
        let first = try XCTUnwrap(cells.allElementsBoundByIndex.first)
        let firstID = first.identifier
        let startY = first.frame.minY

        for _ in 0..<3 { app.swipeUp(velocity: .fast) }
        let moved = app.buttons[firstID]
        XCTAssertTrue(!moved.exists || moved.frame.minY < startY - 100, "a vertical swipe did not scroll the grid")
        for _ in 0..<3 { app.swipeDown(velocity: .fast) }
        XCTAssertTrue(selectedIDs(in: cells).isEmpty, "scrolling selected photos")
    }

    @MainActor
    private func openBlurryAndDark() -> (app: XCUIApplication, cells: XCUIElementQuery) {
        let app = XCUIApplication()
        app.launchArguments = ["-autoScan", "-tinyFingerprints", "-openCategory", "lowQuality"]
        app.launch()
        grantPhotoAccessIfAsked(app)
        let scan = app.buttons["Scan photos"]
        if scan.waitForExistence(timeout: 3) { scan.tap() }

        let cells = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cell-'"))
        XCTAssertTrue(cells.firstMatch.waitForExistence(timeout: 180), "the Blurry and dark list did not open")
        return (app, cells)
    }

    @MainActor
    private func selectedIDs(in cells: XCUIElementQuery) -> Set<String> {
        Set(cells.allElementsBoundByIndex.filter { ($0.value as? String) == "Selected" }.map(\.identifier))
    }
}
