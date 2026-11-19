import Foundation
import Observation
import CrypToadCore

/// The app's single source of truth. Views read from it and call its methods.
///
/// It runs in one of two modes:
/// - **On-device demo** (signed out): the money rules run locally in `CrypToadCore.PortfolioState`.
/// - **Server** (signed in): every money movement goes to the CrypToad backend, which keeps the
///   real double-entry ledger; the app shows (and caches) the server's balances and history.
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

    // MARK: Server account

    /// The signed-in account, or `nil` in on-device demo mode.
    private(set) var account: AccountUser?
    private(set) var bank: BankStatus = .unavailable
    private(set) var serverInfo: ServerInfo?
    private(set) var isSyncing = false
    /// A server action (purchase, trade, sign-in, ...) is in flight.
    private(set) var isWorking = false
    private(set) var lastSyncedAt: Date?

    /// Where the backend lives. Editable in Settings while signed out.
    var serverURLString: String {
        didSet { defaults.set(serverURLString, forKey: Keys.serverURL) }
    }

    var isSignedIn: Bool { api != nil }

    private let priceService: PriceService
    private let localRepository: PortfolioRepository
    private let serverCache: PortfolioRepository
    private let transport: HTTPTransport
    private let defaults: UserDefaults
    private var api: CrypToadAPI?

    private enum Keys {
        static let serverURL = "serverURL"
        static let account = "account"
        static let token = "session-token"
    }

    init(
        priceService: PriceService,
        repository: PortfolioRepository,
        serverCache: PortfolioRepository = InMemoryRepository(),
        transport: HTTPTransport = URLSessionHTTPClient(),
        defaults: UserDefaults = .standard,
        restoreSession: Bool = false
    ) {
        self.priceService = priceService
        self.localRepository = repository
        self.serverCache = serverCache
        self.transport = transport
        self.defaults = defaults
        self.serverURLString = defaults.string(forKey: Keys.serverURL) ?? Self.defaultServerURL

        let saved: PortfolioState? = try? repository.load()
        let local = saved ?? PortfolioState.demo()
        self.state = local
        self.prices = local.lastKnownPrices ?? .placeholder
        if saved == nil { try? repository.save(local) }

        if restoreSession, let token = KeychainStore.read(account: Keys.token), let url = URL(string: serverURLString) {
            api = CrypToadAPI(baseURL: url, token: token, transport: transport)
            account = defaults.data(forKey: Keys.account).flatMap { try? JSONDecoder().decode(AccountUser.self, from: $0) }
            state = (try? serverCache.load()) ?? Self.blankServerState(from: local)
        }
    }

    /// Production store: live CoinGecko prices, saved to Application Support, server session restored.
    static func live() -> PortfolioStore {
        func repository(_ name: String) -> PortfolioRepository {
            guard let url = try? FileRepository.defaultURL() else { return InMemoryRepository() }
            return FileRepository(url: url.deletingLastPathComponent().appendingPathComponent(name))
        }
        return PortfolioStore(
            priceService: CoinGeckoPriceService(),
            repository: repository("portfolio.json"),
            serverCache: repository("server-cache.json"),
            restoreSession: true
        )
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

    /// Fresh in-memory store for UI tests: demo data, fixed prices, talks to the server at the default URL.
    static func uiTesting() -> PortfolioStore {
        let defaults = UserDefaults(suiteName: "ui-testing") ?? .standard
        defaults.removePersistentDomain(forName: "ui-testing")
        let store = preview()
        return PortfolioStore(
            priceService: store.priceService,
            repository: InMemoryRepository(store.state),
            defaults: defaults
        )
    }

    static var defaultServerURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "CrypToadServerURL") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "http://localhost:8000"
    }

    // MARK: Refreshing

    /// Refreshes prices (and server data, when signed in) every `interval` until the task is cancelled.
    /// Attach with `.task { await store.keepPricesFresh() }` so it stops when the view goes away.
    func keepPricesFresh(every interval: Duration = .seconds(60)) async {
        if isSignedIn { await refreshBankStatus() }
        while !Task.isCancelled {
            await refreshAll()
            try? await Task.sleep(for: interval)
        }
    }

    /// Prices, then (when signed in) any due DCA buys and the latest balances and history.
    func refreshAll() async {
        await refreshPrices()
        if isSignedIn {
            await runScheduledServerBuys()
            await syncFromServer()
        }
    }

    func refreshPrices() async {
        if priceStatus != .live { priceStatus = .loading }
        do {
            let snapshot = try await priceService.fetchPrices()
            prices = snapshot
            state.lastKnownPrices = snapshot
            priceStatus = .live
            if !isSignedIn { runScheduledBuys() }
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
        let amount = Decimal(Int.random(in: 350...5_500)) / 100
        let merchant = merchants.randomElement() ?? "Store"

        if isSignedIn {
            Task { await onServer { try await $0.simulateCardPurchase(merchant: merchant, amount: amount) } }
        } else {
            perform { try $0.recordPurchase(merchant: merchant, amount: amount, prices: prices) }
        }
    }

    func simulatePaycheck() {
        if isSignedIn {
            Task { await onServer { try await $0.simulateDeposit(1_250) } }
        } else {
            perform { try $0.deposit(1_250, title: "Paycheck Deposit") }
        }
    }

    func runDCANow() {
        if isSignedIn {
            let dca = state.dca
            Task {
                await onServer { try await $0.invest(dca.amountUSD, allocation: dca.allocation, idempotencyKey: "dca-now-\(UUID().uuidString)") }
            }
        } else {
            perform { try $0.runDCA(prices: prices) }
        }
    }

    /// Local quote, used for the on-device demo.
    func quote(spending usd: Decimal, on asset: Asset) -> TradeQuote? {
        try? Trading.quote(spending: usd, on: asset, prices: prices)
    }

    /// Returns `true` if the trade went through. On-device demo only; signed-in trades use `execute(_:)`.
    @discardableResult
    func executeTrade(_ quote: TradeQuote) -> Bool {
        perform { try $0.executeTrade(quote) }
    }

    /// A rate-locked quote from the server (signed in).
    func serverQuote(spending usd: Decimal, on asset: Asset) async throws -> ServerQuote {
        guard let api else { throw APIError.unauthorized }
        return try await api.quote(spending: usd, on: asset)
    }

    /// Executes a server quote. The quote id doubles as the idempotency key: one quote, at most one trade.
    func execute(_ quote: ServerQuote) async -> Bool {
        await onServer { try await $0.trade(quoteID: quote.id, idempotencyKey: quote.id) }
    }

    // MARK: Settings

    func setRoundUpsEnabled(_ enabled: Bool) {
        update { $0.roundUps.enabled = enabled }
        pushServerSettings()
    }

    func setRoundUpMultiplier(_ multiplier: Int) {
        update { $0.roundUps.multiplier = multiplier }
        pushServerSettings()
    }

    func setRoundUpAllocation(_ allocation: Allocation) {
        guard allocation.isValid else { return fail(PortfolioError.invalidAllocation) }
        update { $0.roundUps.allocation = allocation }
        pushServerSettings()
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
        pushServerSettings()
    }

    func setRequireBiometricUnlock(_ required: Bool) {
        update { $0.requireBiometricUnlock = required }
    }

    /// Wipes saved data and starts over with fresh demo data (on-device demo only).
    func resetDemoData() {
        guard !isSignedIn else { return }
        try? localRepository.reset()
        var fresh = PortfolioState.demo()
        fresh.lastKnownPrices = state.lastKnownPrices
        fresh.requireBiometricUnlock = state.requireBiometricUnlock
        state = fresh
        persist()
    }

    // MARK: Account

    func loadServerInfo() async {
        guard let url = URL(string: serverURLString) else {
            serverInfo = nil
            return
        }
        serverInfo = try? await CrypToadAPI(baseURL: url, transport: transport).info()
    }

    func signInWithApple(identityToken: String, rawNonce: String, fullName: String?) async {
        await signIn { try await $0.signInWithApple(identityToken: identityToken, rawNonce: rawNonce, fullName: fullName) }
    }

    func startDemoAccount() async {
        await signIn { try await $0.createDemoAccount(startingBalance: 1_000) }
    }

    func signOut() async {
        if let api { try? await api.logout() }
        endSession()
    }

    func deleteAccount() async {
        guard let api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await api.deleteAccount()
            endSession()
            alertMessage = "Your CrypToad account was deleted."
        } catch {
            handle(error)
        }
    }

    /// Pulls balances, history, and settings from the server.
    func syncFromServer() async {
        guard let api, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let snapshot = try await api.snapshot()
            state.apply(snapshot)
            lastSyncedAt = Date()
            persist()
        } catch {
            handle(error, quietly: true)
        }
    }

    // MARK: Bank (Plaid)

    func refreshBankStatus() async {
        guard let api else { return }
        if let status = try? await api.bankStatus() { bank = status }
    }

    /// Sandbox: links Plaid's test bank, then pulls its purchases.
    func linkSandboxBank() async {
        guard let api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            bank = try await api.linkSandboxBank()
        } catch {
            return handle(error)
        }
        await syncBank(retryWhilePreparing: true)
    }

    /// Pulls new bank purchases and invests their round-ups.
    func syncBank(retryWhilePreparing: Bool = false) async {
        guard let api else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            var result = try await api.syncBank()
            // A freshly linked sandbox bank takes a few seconds to share its history.
            var attempts = 0
            while retryWhilePreparing, result.isStillPreparing, attempts < 5 {
                attempts += 1
                try await Task.sleep(for: .seconds(2))
                result = try await api.syncBank()
            }
            alertMessage = result.summary
            await refreshBankStatus()
            await syncFromServer()
        } catch {
            handle(error)
        }
    }

    func unlinkBank() async {
        guard let api else { return }
        do {
            try await api.unlinkBank()
            await refreshBankStatus()
        } catch {
            handle(error)
        }
    }

    // MARK: Internals

    private func signIn(_ request: (CrypToadAPI) async throws -> AuthSession) async {
        guard let url = URL(string: serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            alertMessage = "That server address isn't a valid URL."
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let session = try await request(CrypToadAPI(baseURL: url, transport: transport))
            KeychainStore.save(session.token, account: Keys.token)
            defaults.set(try? JSONEncoder().encode(session.user), forKey: Keys.account)
            api = CrypToadAPI(baseURL: url, token: session.token, transport: transport)
            account = session.user
            // The on-device demo stays saved in its own file and comes back on sign-out.
            try? serverCache.reset()
            state = Self.blankServerState(from: state)
            await syncFromServer()
            await refreshBankStatus()
        } catch {
            handle(error)
        }
    }

    private func endSession() {
        KeychainStore.delete(account: Keys.token)
        defaults.removeObject(forKey: Keys.account)
        try? serverCache.reset()
        api = nil
        account = nil
        bank = .unavailable
        lastSyncedAt = nil
        var local = (try? localRepository.load()) ?? PortfolioState.demo()
        local.lastKnownPrices = state.lastKnownPrices
        state = local
    }

    /// An account's view before the first sync: no balances or history, the device's own preferences.
    private static func blankServerState(from local: PortfolioState) -> PortfolioState {
        PortfolioState(
            holdings: Holdings(),
            transactions: [],
            roundUps: local.roundUps,
            dca: local.dca,
            cardFrozen: false,
            requireBiometricUnlock: local.requireBiometricUnlock,
            lastKnownPrices: local.lastKnownPrices
        )
    }

    /// Runs a server action, then refreshes balances and history. Returns `true` on success.
    @discardableResult
    private func onServer(_ work: (CrypToadAPI) async throws -> Void) async -> Bool {
        guard let api else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            try await work(api)
            await syncFromServer()
            return true
        } catch {
            handle(error)
            return false
        }
    }

    private func pushServerSettings() {
        guard let api else { return }
        let settings = ServerSettings(roundUps: state.roundUps, cardFrozen: state.cardFrozen)
        Task {
            do {
                try await api.updateSettings(settings)
            } catch {
                handle(error)
                await syncFromServer()  // put the switches back to what the server has
            }
        }
    }

    /// Executes DCA buys that came due (e.g. while the app was closed) on the server.
    /// Each run has an idempotency key derived from its scheduled date, so it can never execute twice.
    private func runScheduledServerBuys() async {
        guard let api else { return }
        var draft = state
        let due = draft.takeDueDCARuns()
        guard !due.isEmpty else { return }

        var executed: Decimal = 0
        var count = 0
        var skipped = 0
        for date in due {
            do {
                let key = "dca-\(Int(date.timeIntervalSince1970))"
                try await api.invest(state.dca.amountUSD, allocation: state.dca.allocation, idempotencyKey: key)
                executed += state.dca.amountUSD
                count += 1
            } catch let error as APIError where error.code == "insufficient_funds" {
                skipped += 1
            } catch {
                // Offline or server trouble: keep this run due and try again on the next refresh.
                state.dca.nextRun = date
                persist()
                handle(error, quietly: true)
                return
            }
        }
        state.dca.nextRun = draft.dca.nextRun
        persist()

        var messages: [String] = []
        if count > 0 { messages.append("Ran \(count) scheduled DCA buy\(count == 1 ? "" : "s") totaling \(executed.usdString).") }
        if skipped > 0 { messages.append("Skipped \(skipped) scheduled buy\(skipped == 1 ? "" : "s") (not enough USDC).") }
        if !messages.isEmpty { alertMessage = messages.joined(separator: "\n") }
    }

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

    /// Shows an error. An expired session signs the user out; `quietly` hides network errors
    /// from background refreshes so being offline doesn't pop an alert every minute.
    private func handle(_ error: Error, quietly: Bool = false) {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized:
                endSession()
                alertMessage = apiError.localizedDescription
                return
            case .network where quietly:
                return
            default:
                break
            }
        }
        fail(error)
    }

    private func fail(_ error: Error) {
        alertMessage = error.localizedDescription
    }

    private func persist() {
        do {
            try (isSignedIn ? serverCache : localRepository).save(state)
        } catch {
            alertMessage = "Couldn't save your data: \(error.localizedDescription)"
        }
    }
}
