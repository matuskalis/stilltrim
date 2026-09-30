import XCTest

/// Base class of every UI test. The tests delete photos and erase app data, so on a device they would
/// touch the real library. They skip before the first tap anywhere but a simulator. A test that does
/// not derive from this class is a mistake: derive from it.
class SimulatorOnlyTestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        #if !targetEnvironment(simulator)
        throw XCTSkip("These tests delete photos and erase data. They run on the simulator only.")
        #endif
    }
}

extension XCTestCase {
    /// Taps Delete in iOS's own confirmation. The alert animates in, and a tap on it too early is lost,
    /// so this waits until the button can be hit and taps again if the alert is still there.
    @MainActor
    func confirmSystemDeletion() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 120), "iOS did not show its own delete confirmation")
        let delete = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete'")).firstMatch
        let deadline = Date().addingTimeInterval(60)
        while alert.exists, Date() < deadline {
            if delete.isHittable { delete.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTAssertFalse(alert.exists, "the delete confirmation stayed on screen")
    }

    /// Accepts the photo access prompt when the app asks for it. `simctl privacy grant photos` is
    /// ignored by the iOS 26.1 simulator (it writes auth_version 1, PhotoKit wants 2).
    /// The first launch on a freshly erased simulator is slow, so this waits for the app to settle.
    @MainActor
    func grantPhotoAccessIfAsked(_ app: XCUIApplication) {
        let ask = app.buttons["Allow photo access"]
        // A warm cache lets an -autoScan launch finish and open a category before the first look.
        let reviewBar = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Delete ' OR label == 'Select items to delete'")).firstMatch
        let alreadyPastWelcome = [app.buttons["Scan photos"], app.staticTexts["Screenshots"], app.buttons["Cancel"], reviewBar]
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
        // The prompt animates in and a tap on it too early is lost, so tap again until it is gone.
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 60), "The photo access prompt did not appear")
        let allow = alert.buttons["Allow Full Access"]
        let until = Date().addingTimeInterval(60)
        while alert.exists, Date() < until {
            if allow.isHittable { allow.tap() }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
