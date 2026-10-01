import XCTest

@testable import CleanupCore

final class SeenTrackerTests: XCTestCase {
    private let start = ContinuousClock.now
    private let longer = Duration.milliseconds(1200)
    private let shorter = Duration.milliseconds(300)

    func testPhotoThatFlickedThroughInUnderTheMinimumTransitIsNotSeen() {
        var tracker = SeenTracker()
        tracker.appeared("a", at: start)
        tracker.scrolledPast("a", at: start + shorter)
        XCTAssertTrue(tracker.seen.isEmpty)
    }

    func testPhotoThatStayedIsSeen() {
        var tracker = SeenTracker()
        tracker.appeared("a", at: start)
        tracker.scrolledPast("a", at: start + longer)
        XCTAssertEqual(tracker.seen, ["a"])
    }

    func testPhotoReportedPastWithoutEverAppearingIsNotSeen() {
        var tracker = SeenTracker()
        tracker.scrolledPast("a", at: start + longer)
        XCTAssertTrue(tracker.seen.isEmpty)
    }

    func testRepeatedAppearedReportsKeepTheFirstTime() {
        var tracker = SeenTracker()
        tracker.appeared("a", at: start)
        tracker.appeared("a", at: start + shorter)
        tracker.scrolledPast("a", at: start + longer)
        XCTAssertEqual(tracker.seen, ["a"])
    }

    func testReappearingResetsTheClockAndTheSeenState() {
        var tracker = SeenTracker()
        tracker.appeared("a", at: start)
        tracker.scrolledPast("a", at: start + longer)
        let back = start + .seconds(5)
        tracker.appeared("a", at: back)
        XCTAssertTrue(tracker.seen.isEmpty)
        tracker.scrolledPast("a", at: back + shorter)
        XCTAssertTrue(tracker.seen.isEmpty)
    }

    func testPhotoThatLeftBelowLosesItsTime() {
        var tracker = SeenTracker()
        tracker.appeared("a", at: start)
        tracker.disappeared("a")
        tracker.scrolledPast("a", at: start + longer)
        XCTAssertTrue(tracker.seen.isEmpty)
    }

    func testDisappearingKeepsAPhotoThatWasAlreadySeen() {
        var tracker = SeenTracker()
        tracker.appeared("a", at: start)
        tracker.scrolledPast("a", at: start + longer)
        tracker.disappeared("a")
        XCTAssertEqual(tracker.seen, ["a"])
    }
}
