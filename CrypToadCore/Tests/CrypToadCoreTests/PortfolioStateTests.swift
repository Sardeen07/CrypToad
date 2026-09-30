import XCTest
@testable import CrypToadCore

final class PortfolioStateTests: XCTestCase {
    /// Round prices so expected quantities are easy to verify by hand.
    let prices = PriceSnapshot(
        quotes: [
            .btc: PriceQuote(usd: 50_000, change24h: 25),
            .eth: PriceQuote(usd: 2_500),
            .usdc: PriceQuote(usd: 1)
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_790_000_000)
    )

    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func makeState(usdc: Decimal = 100) -> PortfolioState {
        PortfolioState(
            holdings: Holdings([.usdc: usdc]),
            transactions: [],
            roundUps: RoundUpSettings(enabled: true, multiplier: 1, allocation: .balanced),
            dca: DCASettings(enabled: true, amountUSD: 100, frequency: .weekly, allocation: .balanced, nextRun: Date(timeIntervalSince1970: 1_790_000_000))
        )
    }

    // MARK: Purchases + round-ups

    func testPurchaseInvestsRoundUp() throws {
        var state = makeState()
        let tx = try state.recordPurchase(merchant: "Coffee", amount: D("4.25"), prices: prices)

        // 0.75 splits into BTC 0.38 / ETH 0.22 / USDC 0.15.
        XCTAssertEqual(tx.roundUpUSD, D("0.75"))
        XCTAssertEqual(state.holdings[.btc], D("0.0000076"))   // 0.38 / 50,000
        XCTAssertEqual(state.holdings[.eth], D("0.000088"))    // 0.22 / 2,500
        // 100 − 4.25 purchase − 0.75 invested + 0.15 kept as USDC
        XCTAssertEqual(state.holdings[.usdc], D("95.15"))
        XCTAssertEqual(tx.fills.map(\.asset), [.btc, .eth, .usdc])
        XCTAssertEqual(tx.fills.reduce(0) { $0 + $1.costUSD }, D("0.75"))
        XCTAssertEqual(state.roundUpTotal, D("0.75"))
        XCTAssertEqual(state.transactions.first, tx)
        XCTAssertEqual(tx.investedSummary, "Mixed")
    }

    func testPurchaseWithRoundUpsPaused() throws {
        var state = makeState()
        state.roundUps.enabled = false
        let tx = try state.recordPurchase(merchant: "Coffee", amount: D("4.25"), prices: prices)

        XCTAssertEqual(tx.roundUpUSD, 0)
        XCTAssertTrue(tx.fills.isEmpty)
        XCTAssertNil(tx.investedSummary)
        XCTAssertEqual(state.holdings[.usdc], D("95.75"))
    }

    func testRoundUpMultiplier() throws {
        var state = makeState()
        state.roundUps.multiplier = 3
        state.roundUps.allocation = Allocation(btc: 100, eth: 0, usdc: 0)
        let tx = try state.recordPurchase(merchant: "Coffee", amount: D("4.25"), prices: prices)

        XCTAssertEqual(tx.roundUpUSD, D("2.25"))
        XCTAssertEqual(state.holdings[.btc], D("0.000045"))
        XCTAssertEqual(tx.investedSummary, "BTC")
    }

    func testFrozenCardRejectsPurchaseWithoutChangingState() {
        var state = makeState()
        state.cardFrozen = true
        let before = state

        XCTAssertThrowsError(try state.recordPurchase(merchant: "Coffee", amount: 4, prices: prices)) { error in
            XCTAssertEqual(error as? PortfolioError, .cardFrozen)
        }
        XCTAssertEqual(state, before)
    }

    func testInsufficientFundsIncludesRoundUp() {
        var state = makeState(usdc: 5)
        let before = state

        // $4.25 + $0.75 round-up = $5.00 is fine...
        XCTAssertNoThrow(try state.recordPurchase(merchant: "A", amount: D("4.25"), prices: prices))
        // ...but $4.30 + $0.70 = $5.00 now exceeds what's left.
        XCTAssertThrowsError(try state.recordPurchase(merchant: "B", amount: D("4.30"), prices: prices)) { error in
            guard case .insufficientFunds = error as? PortfolioError else { return XCTFail("\(error)") }
        }
        XCTAssertEqual(state.transactions.count, before.transactions.count + 1)
    }

    func testMissingPriceRejectsRoundUp() {
        var state = makeState()
        let noBTC = PriceSnapshot(quotes: [.eth: PriceQuote(usd: 2_500)], fetchedAt: Date())
        let before = state
        XCTAssertThrowsError(try state.recordPurchase(merchant: "Coffee", amount: D("4.25"), prices: noBTC)) { error in
            XCTAssertEqual(error as? PortfolioError, .missingPrice(.btc))
        }
        XCTAssertEqual(state, before)
    }

    func testInvalidPurchaseAmount() {
        var state = makeState()
        XCTAssertThrowsError(try state.recordPurchase(merchant: "Nothing", amount: 0, prices: prices)) { error in
            XCTAssertEqual(error as? PortfolioError, .invalidAmount)
        }
    }

    // MARK: DCA

    func testRunDCA() throws {
        var state = makeState(usdc: 150)
        let tx = try state.runDCA(prices: prices)

        XCTAssertEqual(tx.kind, .dcaBuy)
        XCTAssertEqual(state.holdings[.btc], D("0.001"))   // $50 / 50,000
        XCTAssertEqual(state.holdings[.eth], D("0.012"))   // $30 / 2,500
        XCTAssertEqual(state.holdings[.usdc], 70)          // 150 − 100 + 20
    }

    func testRunDCARequiresFunds() {
        var state = makeState(usdc: 99)
        XCTAssertThrowsError(try state.runDCA(prices: prices))
        XCTAssertEqual(state.holdings[.usdc], 99)
    }

    func testScheduledDCACatchesUpMissedBuys() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = makeState(usdc: 1_000)
        state.dca.nextRun = utc.date(byAdding: .day, value: -15, to: now)!

        let result = state.runScheduledDCA(prices: prices, now: now, calendar: utc)

        // Due at −15, −8 and −1 days.
        XCTAssertEqual(result.executed.count, 3)
        XCTAssertEqual(result.skipped, 0)
        XCTAssertEqual(state.dca.nextRun, utc.date(byAdding: .day, value: 6, to: now))
        XCTAssertEqual(state.holdings[.btc], D("0.003"))
        // Buys are dated when they were due, not when the app caught up.
        XCTAssertEqual(result.executed.first?.date, utc.date(byAdding: .day, value: -15, to: now))
    }

    func testScheduledDCASkipsUnfundedBuys() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = makeState(usdc: 200)
        state.dca.allocation = Allocation(btc: 100, eth: 0, usdc: 0)
        state.dca.nextRun = utc.date(byAdding: .day, value: -15, to: now)!

        let result = state.runScheduledDCA(prices: prices, now: now, calendar: utc)
        XCTAssertEqual(result.executed.count, 2)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertGreaterThan(state.dca.nextRun, now)
    }

    func testScheduledDCADoesNothingWhenDisabledOrNotDue() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var state = makeState(usdc: 1_000)
        state.dca.nextRun = now.addingTimeInterval(60)
        XCTAssertTrue(state.runScheduledDCA(prices: prices, now: now).executed.isEmpty)

        state.dca.enabled = false
        state.dca.nextRun = now.addingTimeInterval(-86_400 * 30)
        XCTAssertTrue(state.runScheduledDCA(prices: prices, now: now).executed.isEmpty)
    }

    func testFrequencies() {
        let start = utc.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        XCTAssertEqual(DCAFrequency.daily.nextDate(after: start, calendar: utc), utc.date(from: DateComponents(year: 2026, month: 2, day: 1)))
        XCTAssertEqual(DCAFrequency.biweekly.nextDate(after: start, calendar: utc), utc.date(from: DateComponents(year: 2026, month: 2, day: 14)))
        // Month-end clamps to the last day of February.
        XCTAssertEqual(DCAFrequency.monthly.nextDate(after: start, calendar: utc), utc.date(from: DateComponents(year: 2026, month: 2, day: 28)))
    }

    // MARK: Trades

    func testTradeQuoteIncludesFee() throws {
        let quote = try Trading.quote(spending: 100, on: .btc, prices: prices)
        XCTAssertEqual(quote.feeUSD, 1)
        XCTAssertEqual(quote.netUSD, 99)
        XCTAssertEqual(quote.quantity, D("0.00198"))
    }

    func testFeeRoundsUpToTheCent() throws {
        let quote = try Trading.quote(spending: D("10.50"), on: .eth, prices: prices)
        XCTAssertEqual(quote.feeUSD, D("0.11"))   // 0.105 → 0.11
    }

    func testExecuteTrade() throws {
        var state = makeState()
        let quote = try Trading.quote(spending: 100, on: .btc, prices: prices)
        let tx = try state.executeTrade(quote)

        XCTAssertEqual(state.holdings[.usdc], 0)
        XCTAssertEqual(state.holdings[.btc], D("0.00198"))
        XCTAssertEqual(tx.feeUSD, 1)
        XCTAssertEqual(tx.kind, .trade)
    }

    func testTradeValidation() throws {
        var state = makeState(usdc: 10)
        XCTAssertThrowsError(try Trading.quote(spending: 0, on: .btc, prices: prices))

        let usdcQuote = try Trading.quote(spending: 5, on: .usdc, prices: prices)
        XCTAssertThrowsError(try state.executeTrade(usdcQuote)) { error in
            XCTAssertEqual(error as? PortfolioError, .unsupportedAsset(.usdc))
        }

        let tooBig = try Trading.quote(spending: 50, on: .eth, prices: prices)
        XCTAssertThrowsError(try state.executeTrade(tooBig))
        XCTAssertEqual(state.holdings[.usdc], 10)
    }

    // MARK: Deposits + valuation

    func testDeposit() throws {
        var state = makeState(usdc: 0)
        let tx = try state.deposit(D("2500.004"))
        XCTAssertEqual(state.holdings[.usdc], 2_500)
        XCTAssertTrue(tx.isCredit)
        XCTAssertThrowsError(try state.deposit(-5))
    }

    func testValuationAnd24hChange() throws {
        var state = makeState(usdc: 10_000)
        state.holdings[.btc] = 1

        XCTAssertEqual(state.totalValue(prices: prices), 60_000)
        // BTC is up 25%: it was worth $40,000 yesterday, so the portfolio gained $10,000 on a $50,000 base.
        let change = try XCTUnwrap(state.change24h(prices: prices))
        XCTAssertEqual(change.amount, 10_000)
        XCTAssertEqual(change.percent, 20)
    }

    func testNo24hChangeWithoutData() {
        let state = makeState()
        XCTAssertNil(state.change24h(prices: .placeholder))
    }

    func testDemoStateIsConsistent() {
        let demo = PortfolioState.demo()
        XCTAssertEqual(demo.transactions.count, 5)
        XCTAssertEqual(demo.roundUpTotal, D("0.86"))
        XCTAssertTrue(demo.dca.allocation.isValid)
        XCTAssertTrue(demo.roundUps.allocation.isValid)
        XCTAssertEqual(demo.transactions, demo.transactions.sorted { $0.date > $1.date })
    }
}
