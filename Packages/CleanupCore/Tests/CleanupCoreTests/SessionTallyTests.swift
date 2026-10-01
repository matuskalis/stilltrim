import XCTest

@testable import CleanupCore

final class SessionTallyTests: XCTestCase {
    func testAddingAccumulatesCountBytesAndBatches() {
        let tally = SessionTally().adding(count: 37, bytes: 120).adding(count: 5, bytes: 30)
        XCTAssertEqual(tally.count, 42)
        XCTAssertEqual(tally.bytes, 150)
        XCTAssertEqual(tally.batches, 2)
    }

    func testStartsEmpty() {
        XCTAssertEqual(SessionTally().batches, 0)
    }
}
