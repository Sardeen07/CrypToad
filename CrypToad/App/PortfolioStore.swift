import Foundation
import Observation
import CrypToadCore

/// The app's single source of truth. Views read from it and call its methods;
/// the actual money rules live in `CrypToadCore.PortfolioState`.
@Observable
@MainActor
final class PortfolioStore {
    enum PriceStatus: Equatable {
        case idle
        case loading
        case live
        case failed(String)
    }

    private(set) var state: PortfolioState
    private(set) var prices: PriceSnapshot
    private(set) var priceStatus: PriceStatus = .idle
    /// A user-facing message for the most recent error or notable event.
    var alertMessage: String?

    private let priceService: PriceService
    private let repository: PortfolioRepository

    init(priceService: PriceService, repository: PortfolioRepository) {
        self.priceService = priceService
        self.repository = repository

        let saved: PortfolioState? = try? repository.load()
        let initial = saved ?? PortfolioState.demo()
        self.state = initial
        self.prices = initial.lastKnownPrices ?? .placeholder

        if saved == nil { persist() }
    }

    /// Production store: live CoinGecko prices, saved to Application Support.
    static func live() -> PortfolioStore {
        let repository: PortfolioRepository
        if let url = try? FileRepository.defaultURL() {
            repository = FileRepository(url: url)
        } else {
            repository = InMemoryRepository()
        }
        return PortfolioStore(priceService: CoinGeckoPriceService(), repository: repository)
    }

    /// In-memory store with fixed prices, for SwiftUI previews.
    static func preview() -> PortfolioStore {
        let snapshot = PriceSnapshot(
            quotes: [
                .btc: PriceQuote(usd: 92_340, change24h: Decimal.exact("2.14")),
                .eth: PriceQuote(usd: 3_120, change24h: Decimal.exact("-1.05")),
                .usdc: PriceQuote(usd: 1, change24h: 0)
            ],
            fetchedAt: Date()
        )
        var demo = PortfolioState.demo()
        demo.lastKnownPrices = snapshot
        return PortfolioStore(priceService: StaticPriceService(snapshot: snapshot), repository: InMemoryRepository(demo))
    }

    // MARK: Prices

    /// Refreshes prices every `interval` seconds until the calling task is cancelled.
    /// Attach with `.task { await store.keepPricesFresh() }` so it stops when the view goes away.
    func keepPricesFresh(every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await refreshPrices()
            try? await Task.sleep(for: interval)
        }
    }

    func refreshPrices() async {
        if priceStatus != .live { priceStatus = .loading }
        do {
            let snapshot = try await priceService.fetchPrices()
            prices = snapshot
            state.lastKnownPrices = snapshot
            priceStatus = .live
            runScheduledBuys()
            persist()
        } catch {
            priceStatus = .failed(error.localizedDescription)
        }
    }

    var isUsingLivePrices: Bool {
        priceStatus == .live && !prices.isPlaceholder
    }

    // MARK: Portfolio

    var totalValue: Decimal { state.totalValue(prices: prices) }
    var change24h: (amount: Decimal, percent: Decimal)? { state.change24h(prices: prices) }

    func value(of asset: Asset) -> Decimal { state.value(of: asset, prices: prices) }

    // MARK: Actions

    func simulatePurchase() {
        let merchants = ["Whole Foods", "Shell", "Target", "Chipotle", "Starbucks", "Trader Joe's", "Apple Store", "Uber"]
        let cents = Int.random(in: 350...5_500)
        let amount = Decimal(cents) / 100
        let merchant = merchants.randomElement() ?? "Store"

        perform { try $0.recordPurchase(merchant: merchant, amount: amount, prices: prices) }
    }

    func simulatePaycheck() {
        perform { try $0.deposit(1_250, title: "Paycheck Deposit") }
    }

    func runDCANow() {
        perform { try $0.runDCA(prices: prices) }
    }

    func quote(spending usd: Decimal, on asset: Asset) -> TradeQuote? {
        try? Trading.quote(spending: usd, on: asset, prices: prices)
    }

    /// Returns `true` if the trade went through.
    @discardableResult
    func executeTrade(_ quote: TradeQuote) -> Bool {
        perform { try $0.executeTrade(quote) }
    }

    // MARK: Settings

    func setRoundUpsEnabled(_ enabled: Bool) {
        update { $0.roundUps.enabled = enabled }
    }

    func setRoundUpMultiplier(_ multiplier: Int) {
        update { $0.roundUps.multiplier = multiplier }
    }

    func setRoundUpAllocation(_ allocation: Allocation) {
        guard allocation.isValid else { return fail(PortfolioError.invalidAllocation) }
        update { $0.roundUps.allocation = allocation }
    }

    func setDCAEnabled(_ enabled: Bool) {
        update { state in
            state.dca.enabled = enabled
            // Don't fire a pile of missed buys the moment DCA is switched back on.
            if enabled && state.dca.nextRun < Date() {
                state.dca.nextRun = state.dca.frequency.nextDate(after: Date())
            }
        }
    }

    func setDCAAllocation(_ allocation: Allocation) {
        guard allocation.isValid else { return fail(PortfolioError.invalidAllocation) }
        update { $0.dca.allocation = allocation }
    }

    func setDCASchedule(amount: Decimal, frequency: DCAFrequency) {
        guard amount.cents > 0 else { return fail(PortfolioError.invalidAmount) }
        update { state in
            let changedFrequency = state.dca.frequency != frequency
            state.dca.amountUSD = amount.cents
            state.dca.frequency = frequency
            if changedFrequency {
                state.dca.nextRun = frequency.nextDate(after: Date())
            }
        }
    }

    func setCardFrozen(_ frozen: Bool) {
        update { $0.cardFrozen = frozen }
    }

    func setRequireBiometricUnlock(_ required: Bool) {
        update { $0.requireBiometricUnlock = required }
    }

    /// Wipes saved data and starts over with fresh demo data.
    func resetDemoData() {
        try? repository.reset()
        var fresh = PortfolioState.demo()
        fresh.lastKnownPrices = state.lastKnownPrices
        fresh.requireBiometricUnlock = state.requireBiometricUnlock
        state = fresh
        persist()
    }

    // MARK: Internals

    private func runScheduledBuys() {
        let result = state.runScheduledDCA(prices: prices)
        if !result.executed.isEmpty {
            let total = result.executed.reduce(Decimal(0)) { $0 + $1.amountUSD }
            let count = result.executed.count
            alertMessage = "Ran \(count) scheduled DCA buy\(count == 1 ? "" : "s") totaling \(total.usdString)."
        }
        if result.skipped > 0 {
            alertMessage = (alertMessage.map { $0 + "\n" } ?? "") +
                "Skipped \(result.skipped) scheduled buy\(result.skipped == 1 ? "" : "s") (not enough USDC)."
        }
    }

    /// Runs a throwing ledger operation. On failure the state is untouched and the error is shown.
    @discardableResult
    private func perform<T>(_ operation: (inout PortfolioState) throws -> T) -> Bool {
        var draft = state
        do {
            _ = try operation(&draft)
            state = draft
            persist()
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func update(_ change: (inout PortfolioState) -> Void) {
        change(&state)
        persist()
    }

    private func fail(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    private func persist() {
        do {
            try repository.save(state)
        } catch {
            alertMessage = "Couldn't save your data: \(error.localizedDescription)"
        }
    }
}
