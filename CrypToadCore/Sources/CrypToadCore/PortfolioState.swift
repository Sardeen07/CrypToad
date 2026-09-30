import Foundation

/// Everything the app knows about the user's account, plus the rules that change it.
///
/// All mutations go through the methods below, which validate first and only then
/// change balances, so a failed operation never leaves the ledger half-updated.
public struct PortfolioState: Codable, Equatable, Sendable {
    public var holdings: Holdings
    /// Newest first.
    public var transactions: [TransactionRecord]
    public var roundUps: RoundUpSettings
    public var dca: DCASettings
    public var cardFrozen: Bool
    public var requireBiometricUnlock: Bool
    /// Most recent successful price fetch, so the app can show real numbers when offline.
    public var lastKnownPrices: PriceSnapshot?

    public init(
        holdings: Holdings,
        transactions: [TransactionRecord],
        roundUps: RoundUpSettings,
        dca: DCASettings,
        cardFrozen: Bool = false,
        requireBiometricUnlock: Bool = false,
        lastKnownPrices: PriceSnapshot? = nil
    ) {
        self.holdings = holdings
        self.transactions = transactions
        self.roundUps = roundUps
        self.dca = dca
        self.cardFrozen = cardFrozen
        self.requireBiometricUnlock = requireBiometricUnlock
        self.lastKnownPrices = lastKnownPrices
    }

    // MARK: Derived values

    public var roundUpTotal: Decimal {
        transactions.reduce(0) { $0 + $1.roundUpUSD }
    }

    public var roundUpTransactions: [TransactionRecord] {
        transactions.filter { $0.roundUpUSD > 0 }
    }

    // MARK: Card purchases

    /// Records a card purchase paid from the USDC balance and invests its round-up.
    @discardableResult
    public mutating func recordPurchase(
        merchant: String,
        amount: Decimal,
        prices: PriceSnapshot,
        date: Date = Date()
    ) throws -> TransactionRecord {
        guard !cardFrozen else { throw PortfolioError.cardFrozen }
        let price = amount.cents
        guard price > 0 else { throw PortfolioError.invalidAmount }

        let spare = roundUps.enabled ? RoundUp.spareChange(for: price, multiplier: roundUps.multiplier) : 0
        let needed = price + spare
        guard holdings[.usdc] >= needed else {
            throw PortfolioError.insufficientFunds(needed: needed, available: holdings[.usdc])
        }
        if spare > 0 {
            try Self.checkPrices(for: roundUps.allocation, in: prices)
        }

        holdings[.usdc] -= price
        let fills = spare > 0 ? invest(spare, allocation: roundUps.allocation, prices: prices) : []

        let transaction = TransactionRecord(kind: .purchase, date: date, title: merchant, amountUSD: price, roundUpUSD: spare, fills: fills)
        transactions.insert(transaction, at: 0)
        return transaction
    }

    // MARK: Dollar-cost averaging

    /// Executes one DCA buy right now without changing the schedule.
    @discardableResult
    public mutating func runDCA(prices: PriceSnapshot, date: Date = Date()) throws -> TransactionRecord {
        let amount = dca.amountUSD.cents
        guard amount > 0 else { throw PortfolioError.invalidAmount }
        guard dca.allocation.isValid else { throw PortfolioError.invalidAllocation }
        guard holdings[.usdc] >= amount else {
            throw PortfolioError.insufficientFunds(needed: amount, available: holdings[.usdc])
        }
        try Self.checkPrices(for: dca.allocation, in: prices)

        let fills = invest(amount, allocation: dca.allocation, prices: prices)
        let transaction = TransactionRecord(kind: .dcaBuy, date: date, title: "Auto-Investment (DCA)", amountUSD: amount, fills: fills)
        transactions.insert(transaction, at: 0)
        return transaction
    }

    /// Runs every scheduled DCA buy that came due before `now` (e.g. while the app was closed)
    /// and advances the schedule. Buys that can't be funded are skipped.
    ///
    /// - Returns: The buys that executed and how many due buys were skipped.
    @discardableResult
    public mutating func runScheduledDCA(
        prices: PriceSnapshot,
        now: Date = Date(),
        calendar: Calendar = .current,
        maxCatchUp: Int = 12
    ) -> (executed: [TransactionRecord], skipped: Int) {
        guard dca.enabled else { return ([], 0) }
        var executed: [TransactionRecord] = []
        var skipped = 0
        var iterations = 0

        while dca.nextRun <= now {
            if iterations < maxCatchUp, let tx = try? runDCA(prices: prices, date: dca.nextRun) {
                executed.append(tx)
            } else {
                skipped += 1
            }
            dca.nextRun = dca.frequency.nextDate(after: dca.nextRun, calendar: calendar)
            iterations += 1
        }
        return (executed, skipped)
    }

    // MARK: Trades and deposits

    /// Converts USDC into BTC or ETH at a previously shown quote.
    @discardableResult
    public mutating func executeTrade(_ quote: TradeQuote, date: Date = Date()) throws -> TransactionRecord {
        guard !quote.asset.isStablecoin else { throw PortfolioError.unsupportedAsset(quote.asset) }
        guard quote.spendUSD >= Trading.minimumTradeUSD, quote.quantity > 0 else { throw PortfolioError.invalidAmount }
        guard holdings[.usdc] >= quote.spendUSD else {
            throw PortfolioError.insufficientFunds(needed: quote.spendUSD, available: holdings[.usdc])
        }

        holdings[.usdc] -= quote.spendUSD
        holdings[quote.asset] += quote.quantity

        let fill = Fill(asset: quote.asset, quantity: quote.quantity, priceUSD: quote.priceUSD, costUSD: quote.netUSD)
        let transaction = TransactionRecord(
            kind: .trade,
            date: date,
            title: "Bought \(quote.asset.displayName)",
            amountUSD: quote.spendUSD,
            feeUSD: quote.feeUSD,
            fills: [fill]
        )
        transactions.insert(transaction, at: 0)
        return transaction
    }

    /// Credits an incoming deposit (e.g. a paycheck) to the USDC balance.
    @discardableResult
    public mutating func deposit(_ amount: Decimal, title: String = "Paycheck Deposit", date: Date = Date()) throws -> TransactionRecord {
        let value = amount.cents
        guard value > 0 else { throw PortfolioError.invalidAmount }
        holdings[.usdc] += value
        let transaction = TransactionRecord(kind: .deposit, date: date, title: title, amountUSD: value)
        transactions.insert(transaction, at: 0)
        return transaction
    }

    // MARK: Valuation

    public func value(of asset: Asset, prices: PriceSnapshot) -> Decimal {
        guard let price = prices.price(of: asset) else { return 0 }
        return (holdings[asset] * price).cents
    }

    public func totalValue(prices: PriceSnapshot) -> Decimal {
        Asset.allCases.reduce(0) { $0 + value(of: $1, prices: prices) }
    }

    /// Dollar and percent change of the whole portfolio over 24 hours, derived from
    /// each asset's 24h price change. `nil` if no change data is available.
    public func change24h(prices: PriceSnapshot) -> (amount: Decimal, percent: Decimal)? {
        var delta: Decimal = 0
        var hasData = false

        for asset in Asset.allCases {
            guard let pct = prices.change24h(of: asset) else { continue }
            hasData = true
            let current = value(of: asset, prices: prices)
            let previous = current / (1 + pct / 100)
            delta += current - previous
        }
        guard hasData else { return nil }

        let total = totalValue(prices: prices)
        let base = total - delta
        let percent = base > 0 ? (delta / base * 100).rounded(2) : 0
        return (delta.cents, percent)
    }

    // MARK: Internals

    private static func checkPrices(for allocation: Allocation, in prices: PriceSnapshot) throws {
        for asset in Asset.allCases where allocation[asset] > 0 {
            guard prices.price(of: asset) != nil else { throw PortfolioError.missingPrice(asset) }
        }
    }

    /// Moves `usd` out of the USDC balance and into assets per `allocation`.
    /// Callers must have validated funds and prices first.
    private mutating func invest(_ usd: Decimal, allocation: Allocation, prices: PriceSnapshot) -> [Fill] {
        holdings[.usdc] -= usd
        var fills: [Fill] = []

        for (asset, share) in allocation.split(usd).sorted(by: { $0.key.rawValue < $1.key.rawValue }) where share > 0 {
            let price = prices.price(of: asset) ?? 1
            let quantity = asset.isStablecoin ? share : (share / price).rounded(asset.precision, .down)
            holdings[asset] += quantity
            fills.append(Fill(asset: asset, quantity: quantity, priceUSD: price, costUSD: share))
        }
        return fills
    }
}

// MARK: - Demo data

extension PortfolioState {
    /// Starting data for a fresh install, dated relative to `now`.
    public static func demo(now: Date = Date(), calendar: Calendar = .current) -> PortfolioState {
        let D = Decimal.exact
        func daysAgo(_ days: Int, hour: Int = 12) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }

        let transactions: [TransactionRecord] = [
            TransactionRecord(kind: .purchase, date: daysAgo(0, hour: 8), title: "Starbucks", amountUSD: D("4.25"), roundUpUSD: D("0.75"),
                        fills: [Fill(asset: .btc, quantity: D("0.00000812"), priceUSD: 92_340, costUSD: D("0.75"))]),
            TransactionRecord(kind: .purchase, date: daysAgo(1), title: "Amazon", amountUSD: D("47.89"), roundUpUSD: D("0.11"),
                        fills: [Fill(asset: .eth, quantity: D("0.00003525"), priceUSD: 3_120, costUSD: D("0.11"))]),
            TransactionRecord(kind: .dcaBuy, date: daysAgo(2, hour: 9), title: "Auto-Investment (DCA)", amountUSD: 100,
                        fills: [
                            Fill(asset: .btc, quantity: D("0.00054147"), priceUSD: 92_340, costUSD: 50),
                            Fill(asset: .eth, quantity: D("0.00961538"), priceUSD: 3_120, costUSD: 30),
                            Fill(asset: .usdc, quantity: 20, priceUSD: 1, costUSD: 20)
                        ]),
            TransactionRecord(kind: .deposit, date: daysAgo(3, hour: 6), title: "Paycheck Deposit", amountUSD: 2_500),
            TransactionRecord(kind: .p2pSent, date: daysAgo(4, hour: 19), title: "Sarah K.", amountUSD: 25)
        ]

        return PortfolioState(
            holdings: Holdings([.usdc: D("1234.56"), .btc: D("0.0234"), .eth: D("0.456")]),
            transactions: transactions,
            roundUps: RoundUpSettings(enabled: true, multiplier: 1, allocation: .balanced),
            dca: DCASettings(
                enabled: true,
                amountUSD: 100,
                frequency: .weekly,
                allocation: .balanced,
                nextRun: calendar.date(byAdding: .day, value: 5, to: daysAgo(0, hour: 9)) ?? now
            )
        )
    }
}
