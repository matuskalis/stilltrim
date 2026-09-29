import XCTest

extension XCTestCase {
    /// Accepts the photo access prompt when the app asks for it. `simctl privacy grant photos` is
    /// ignored by the iOS 26.1 simulator (it writes auth_version 1, PhotoKit wants 2).
    /// The first launch on a freshly erased simulator is slow, so this waits for the app to settle.
    @MainActor
    func grantPhotoAccessIfAsked(_ app: XCUIApplication) {
        let ask = app.buttons["Allow photo access"]
        let alreadyPastWelcome = [app.buttons["Scan photos"], app.staticTexts["Screenshots"], app.buttons["Cancel"]]
        let deadline = Date().addingTimeInterval(45)
        while Date() < deadline {
            if ask.exists { break }
            if alreadyPastWelcome.contains(where: \.exists) { return }
            if app.buttons["Open Settings"].exists {
                XCTFail("Photo access was denied earlier. Reset it: xcrun simctl privacy <udid> reset photos <bundle id>")
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        guard ask.exists else {
            XCTFail("Neither the welcome screen nor the home screen appeared within 45 seconds")
            return
        }
        ask.tap()
        let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow Full Access"]
        XCTAssertTrue(allow.waitForExistence(timeout: 20), "The photo access prompt did not appear")
        allow.tap()
    }
}
