import XCTest

/// Visits every screen of the on-device demo and attaches a screenshot of each.
/// Runs without a backend. Use it to review the UI after design changes:
///
///     xcodebuild test -scheme CrypToad -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
///       -only-testing:CrypToadUITests/ScreenTourUITests -resultBundlePath tour.xcresult
///     xcrun xcresulttool export attachments --path tour.xcresult --output-path tour
final class ScreenTourUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    /// In the simulator's current appearance.
    func testTour() { tour(name: "tour") }
    func testTourDark() { tour(name: "dark", arguments: ["-force-dark"]) }
    /// Accessibility text size, to check layouts hold up under Dynamic Type.
    func testTourLargeText() { tour(name: "large-text", arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]) }

    private func tour(name mode: String, arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()

        XCTAssertTrue(element("Portfolio").waitForExistence(timeout: 10) || element("Total").waitForExistence(timeout: 2))
        shot("\(mode)-01-home")
        app.swipeUp()
        shot("\(mode)-02-home-scrolled")

        if tapFirst(["See All", "View All Transactions"]) {
            sleep(1)
            shot("\(mode)-03-activity")
            goBack()
        }
        app.swipeDown()

        for (index, tab) in ["Invest", "Round-Ups", "Card"].enumerated() where tapTab(tab) {
            sleep(1)
            shot("\(mode)-0\(index + 4)-\(tab.lowercased())")
            app.swipeUp()
            shot("\(mode)-0\(index + 4)-\(tab.lowercased())-scrolled")
        }

        tapTab("Home")
        if tapFirst(["Buy", "Buy BTC / ETH"]) {
            sleep(1)
            shot("\(mode)-07-trade")
            tapFirst(["Cancel"])
        }

        if tapFirst(["Settings"]) {
            sleep(1)
            shot("\(mode)-08-settings")
            tapFirst(["Done"])
        }
    }

    // MARK: Helpers

    private func element(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @discardableResult
    private func tapTab(_ name: String) -> Bool {
        let tab = app.tabBars.buttons[name]
        if tab.exists { tab.tap(); return true }
        // Legacy custom tab bar: a button whose label ends with the tab name.
        let alt = name == "Round-Ups" ? "Round-Up" : name
        let button = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@ AND NOT (label BEGINSWITH 'Back')", alt)).firstMatch
        if button.exists { button.tap(); return true }
        return false
    }

    @discardableResult
    private func tapFirst(_ labels: [String]) -> Bool {
        for label in labels {
            let exact = app.buttons[label]
            if exact.exists && exact.isHittable { exact.tap(); return true }
        }
        for label in labels {
            let match = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            if match.exists && match.isHittable { match.tap(); return true }
        }
        return false
    }

    private func goBack() {
        let back = app.navigationBars.buttons.firstMatch
        if back.exists && back.isHittable { back.tap() } else { tapTab("Home") }
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
