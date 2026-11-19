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
    /// Dark mode via the app's Appearance setting, preset from the launch arguments.
    func testTourDark() { tour(name: "dark", arguments: ["-appearance", "dark"]) }

    /// Settings → Appearance actually switches the app between light and dark.
    func testAppearanceSetting() {
        // No -appearance argument here: launch arguments override saved settings, which would
        // hide the choice made in Settings. The simulator itself is in light mode.
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        tapTab("Home")
        XCTAssertTrue(element("Portfolio").waitForExistence(timeout: 10))
        XCTAssertGreaterThan(backgroundBrightness(), 0.8, "starts light")

        for (choice, expectDark) in [("Dark", true), ("Light", false)] {
            app.buttons["Settings"].tap()
            let segment = app.buttons[choice]
            XCTAssertTrue(segment.waitForExistence(timeout: 5))
            segment.tap()
            app.buttons["Done"].tap()
            sleep(1)
            let brightness = backgroundBrightness()
            if expectDark {
                XCTAssertLessThan(brightness, 0.2, "Dark should darken the app")
                shot("appearance-dark")
            } else {
                XCTAssertGreaterThan(brightness, 0.8, "Light should brighten the app")
            }
        }
    }
    /// Accessibility text size, to check layouts hold up under Dynamic Type.
    func testTourLargeText() { tour(name: "large-text", arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]) }

    private func tour(name mode: String, arguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"] + arguments
        app.launch()
        tapTab("Home")  // iOS may restore the last tab

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

    /// Brightness (0–1) of the page background at the left margin, halfway down the screen.
    private func backgroundBrightness() -> CGFloat {
        let image = app.screenshot().image
        guard let cg = image.cgImage else { return -1 }
        let x = Int(6 * image.scale), y = cg.height / 2
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(cg, in: CGRect(x: -x, y: -(cg.height - y - 1), width: cg.width, height: cg.height))
        return (CGFloat(pixel[0]) + CGFloat(pixel[1]) + CGFloat(pixel[2])) / (3 * 255)
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
