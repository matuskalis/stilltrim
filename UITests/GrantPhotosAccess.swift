import XCTest

/// Grants photo access once per simulator and checks the app reaches the home screen.
final class GrantPhotosAccess: SimulatorOnlyTestCase {
    @MainActor
    func testGrantFullAccess() {
        let app = XCUIApplication()
        app.launch()
        grantPhotoAccessIfAsked(app)
        XCTAssertTrue(app.buttons["Scan photos"].waitForExistence(timeout: 20))
    }
}
