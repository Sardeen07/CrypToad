import XCTest
@testable import CrypToadCore

final class PersistenceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// Whole-second dates, since ISO 8601 storage drops fractional seconds.
    private func sampleState() -> PortfolioState {
        var state = PortfolioState.demo(now: Date(timeIntervalSince1970: 1_790_000_000))
        state.cardFrozen = true
        state.requireBiometricUnlock = true
        state.lastKnownPrices = PriceSnapshot(
            quotes: [.btc: PriceQuote(usd: D("92340.12"), change24h: D("-1.5"))],
            fetchedAt: Date(timeIntervalSince1970: 1_790_000_100)
        )
        return state
    }

    func testMissingFileLoadsNil() throws {
        let repo = FileRepository(url: directory.appendingPathComponent("portfolio.json"))
        XCTAssertNil(try repo.load())
    }

    func testRoundTripPreservesEverythingExactly() throws {
        let repo = FileRepository(url: directory.appendingPathComponent("nested/portfolio.json"))
        let state = sampleState()

        try repo.save(state)
        let loaded = try XCTUnwrap(try repo.load())

        XCTAssertEqual(loaded, state)
        // 8-decimal crypto quantities survive the JSON round trip.
        XCTAssertEqual(loaded.transactions[0].fills[0].quantity, D("0.00000812"))
        XCTAssertEqual(loaded.holdings[.usdc], D("1234.56"))
    }

    func testReset() throws {
        let repo = FileRepository(url: directory.appendingPathComponent("portfolio.json"))
        try repo.save(sampleState())
        try repo.reset()
        XCTAssertNil(try repo.load())
        XCTAssertNoThrow(try repo.reset())   // resetting twice is fine
    }

    func testInMemoryRepository() throws {
        let repo = InMemoryRepository()
        let state = sampleState()
        XCTAssertNil(try repo.load())
        try repo.save(state)
        XCTAssertEqual(try repo.load(), state)
    }
}
