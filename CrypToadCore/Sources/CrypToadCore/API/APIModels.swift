import Foundation

// Types returned by the CrypToad backend (see backend/README.md), already converted
// to the app's own models. Money arrives as decimal strings and is parsed straight
// into `Decimal`, never through `Double`.

/// The signed-in user.
public struct AccountUser: Codable, Hashable, Sendable {
    public var userID: Int
    public var email: String?
    public var displayName: String?
    public var kycStatus: String
    /// "apple" or "demo".
    public var signInMethod: String

    public init(userID: Int, email: String?, displayName: String?, kycStatus: String, signInMethod: String) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
        self.kycStatus = kycStatus
        self.signInMethod = signInMethod
    }

    /// Best label for the account in the UI.
    public var label: String {
        if let displayName, !displayName.isEmpty { return displayName }
        if let email, !email.isEmpty { return email }
        return signInMethod == "demo" ? "Demo account" : "Apple ID"
    }
}

/// A new session: the bearer token (store it in the Keychain) plus the user.
public struct AuthSession: Hashable, Sendable {
    public var token: String
    public var user: AccountUser
    public var created: Bool
}

/// What the server supports.
public struct ServerInfo: Hashable, Sendable {
    public var version: String
    public var demoAccounts: Bool
    public var bankLinking: Bool
    public var plaidEnvironment: String?
}

/// Round-up and card settings, which live on the server because purchases arrive there.
public struct ServerSettings: Hashable, Sendable {
    public var roundUps: RoundUpSettings
    public var cardFrozen: Bool

    public init(roundUps: RoundUpSettings, cardFrozen: Bool) {
        self.roundUps = roundUps
        self.cardFrozen = cardFrozen
    }
}

/// A server-side quote: the rate is locked until `expiresAt`.
public struct ServerQuote: Hashable, Sendable, Identifiable {
    public var id: String
    public var expiresAt: Date
    public var quote: TradeQuote

    public func isExpired(now: Date = Date()) -> Bool { now >= expiresAt }
}

/// The state of the user's linked bank account (Plaid).
public struct BankStatus: Hashable, Sendable {
    public var linked: Bool
    /// Whether the server has bank linking configured at all.
    public var available: Bool
    public var sandbox: Bool
    public var institutionName: String?
    public var linkedAt: Date?
    public var lastSyncedAt: Date?

    public static let unavailable = BankStatus(linked: false, available: false, sandbox: false)

    public init(linked: Bool, available: Bool, sandbox: Bool, institutionName: String? = nil, linkedAt: Date? = nil, lastSyncedAt: Date? = nil) {
        self.linked = linked
        self.available = available
        self.sandbox = sandbox
        self.institutionName = institutionName
        self.linkedAt = linkedAt
        self.lastSyncedAt = lastSyncedAt
    }
}

/// The outcome of pulling new bank transactions.
public struct BankSyncResult: Hashable, Sendable {
    /// Plaid's update status. `NOT_READY` means Plaid is still fetching the history; try again shortly.
    public var status: String
    public var added: Int
    public var roundedUp: Int
    public var skipped: Int
    public var totalRoundUp: Decimal

    public var isStillPreparing: Bool { status == "NOT_READY" && added == 0 }

    /// One-line summary for an alert.
    public var summary: String {
        if isStillPreparing { return "Your bank is still sharing its transactions. Try syncing again in a few seconds." }
        if added == 0 { return "No new bank purchases." }
        var text = "Found \(added) new purchase\(added == 1 ? "" : "s")"
        text += roundedUp > 0 ? " and invested \(totalRoundUp.usdString) in spare change." : "."
        if skipped > 0 { text += " Skipped \(skipped) round-up\(skipped == 1 ? "" : "s") (not enough USDC)." }
        return text
    }
}

/// Everything the app shows, as one consistent snapshot from the server.
public struct ServerSnapshot: Hashable, Sendable {
    public var holdings: Holdings
    public var transactions: [TransactionRecord]
    public var settings: ServerSettings

    public init(holdings: Holdings, transactions: [TransactionRecord], settings: ServerSettings) {
        self.holdings = holdings
        self.transactions = transactions
        self.settings = settings
    }
}

extension PortfolioState {
    /// Replaces balances, history, and server-owned settings with the server's copy.
    /// DCA settings and app preferences stay on the device.
    public mutating func apply(_ snapshot: ServerSnapshot) {
        holdings = snapshot.holdings
        transactions = snapshot.transactions
        roundUps = snapshot.settings.roundUps
        cardFrozen = snapshot.settings.cardFrozen
    }

    /// Advances the DCA schedule past every run that is due and returns those run dates
    /// (at most `maxCatchUp`), for the app to execute on the server.
    public mutating func takeDueDCARuns(now: Date = Date(), calendar: Calendar = .current, maxCatchUp: Int = 12) -> [Date] {
        guard dca.enabled else { return [] }
        var due: [Date] = []
        while dca.nextRun <= now {
            if due.count < maxCatchUp { due.append(dca.nextRun) }
            dca.nextRun = dca.frequency.nextDate(after: dca.nextRun, calendar: calendar)
        }
        return due
    }
}
