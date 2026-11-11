import XCTest

/// End-to-end: the real app talking to a real backend on http://localhost:8000.
///
/// Start the backend first (it's skipped otherwise):
///     cd backend && docker compose up        # or: uvicorn app.main:create_app --factory
/// then run: xcodebuild test -scheme CrypToad -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
final class ServerFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(Self.backendIsRunning(), "Backend not running on localhost:8000")
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func testDemoAccountPurchaseTradeAndSignOut() throws {
        XCTAssertTrue(element("On-device demo").waitForExistence(timeout: 10))

        // Sign in with a demo account.
        app.buttons["Settings"].tap()
        let demoButton = element("Try a demo account")
        XCTAssertTrue(demoButton.waitForExistence(timeout: 5))
        demoButton.tap()
        XCTAssertTrue(element("Signed in as").waitForExistence(timeout: 15), "demo sign-in should succeed")
        snapshot("1-settings-signed-in")
        app.buttons["Done"].tap()

        // The home screen now shows the server's account: the $1,000 welcome deposit.
        XCTAssertTrue(element("Synced").waitForExistence(timeout: 5))
        XCTAssertTrue(element("Welcome Bonus (Demo)").waitForExistence(timeout: 10))
        snapshot("2-home-synced")

        // A card swipe goes to the server and comes back with its round-up.
        element("Simulate Purchase").tap()
        let merchants = ["Whole Foods", "Shell", "Target", "Chipotle", "Starbucks", "Trader Joe's", "Apple Store", "Uber"]
        let purchase = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label MATCHES %@", ".*(\(merchants.joined(separator: "|"))).*"))
            .firstMatch
        XCTAssertTrue(purchase.waitForExistence(timeout: 10), "the purchase should appear in recent activity")

        // Buy BTC at a rate-locked server quote.
        element("Buy BTC / ETH").tap()
        XCTAssertTrue(element("Rate locked by the server").waitForExistence(timeout: 10), "server quote should load")
        snapshot("3-trade-server-quote")
        app.navigationBars.buttons["Buy"].tap()
        XCTAssertTrue(element("Bought Bitcoin").waitForExistence(timeout: 10), "the trade should appear in recent activity")
        snapshot("4-home-after-trade")

        // Signing out returns to the on-device demo.
        app.buttons["Settings"].tap()
        let signOut = app.buttons["Sign out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5))
        signOut.tap()
        XCTAssertTrue(element("Try a demo account").waitForExistence(timeout: 10))
        app.buttons["Done"].tap()
        XCTAssertTrue(element("On-device demo").waitForExistence(timeout: 5))
    }

    // MARK: Helpers

    /// Any element whose accessibility label contains `text`.
    private func element(_ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static func backendIsRunning() -> Bool {
        let done = DispatchSemaphore(value: 0)
        var ok = false
        var request = URLRequest(url: URL(string: "http://localhost:8000/health")!)
        request.timeoutInterval = 3
        URLSession.shared.dataTask(with: request) { _, response, _ in
            ok = (response as? HTTPURLResponse)?.statusCode == 200
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 5)
        return ok
    }
}
