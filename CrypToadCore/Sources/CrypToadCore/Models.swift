import Foundation

/// Quantity held of each asset. Missing assets read as zero.
public struct Holdings: Codable, Hashable, Sendable {
    public private(set) var amounts: [Asset: Decimal]

    public init(_ amounts: [Asset: Decimal] = [:]) {
        self.amounts = amounts
    }

    public subscript(asset: Asset) -> Decimal {
        get { amounts[asset] ?? 0 }
        set { amounts[asset] = newValue }
    }
}

/// One asset bought as part of a transaction.
public struct Fill: Codable, Hashable, Sendable {
    public var asset: Asset
    public var quantity: Decimal
    public var priceUSD: Decimal
    /// Dollars spent on this fill.
    public var costUSD: Decimal

    public init(asset: Asset, quantity: Decimal, priceUSD: Decimal, costUSD: Decimal) {
        self.asset = asset
        self.quantity = quantity
        self.priceUSD = priceUSD
        self.costUSD = costUSD
    }
}

public struct TransactionRecord: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        /// Card purchase (may carry a round-up).
        case purchase
        /// Scheduled dollar-cost-average buy.
        case dcaBuy
        /// Manual USDC → BTC/ETH trade.
        case trade
        /// Paycheck or other incoming deposit.
        case deposit
        /// Peer-to-peer payment sent.
        case p2pSent
    }

    public let id: UUID
    public var kind: Kind
    public var date: Date
    /// Merchant, recipient, or a description.
    public var title: String
    /// Dollar amount of the transaction itself (purchase price, DCA amount, deposit, ...).
    public var amountUSD: Decimal
    /// Spare change invested from this purchase (0 if none).
    public var roundUpUSD: Decimal
    /// Conversion fee charged.
    public var feeUSD: Decimal
    /// Crypto acquired by this transaction (DCA buys, trades, and round-ups).
    public var fills: [Fill]

    public init(
        id: UUID = UUID(),
        kind: Kind,
        date: Date,
        title: String,
        amountUSD: Decimal,
        roundUpUSD: Decimal = 0,
        feeUSD: Decimal = 0,
        fills: [Fill] = []
    ) {
        self.id = id
        self.kind = kind
        self.date = date
        self.title = title
        self.amountUSD = amountUSD
        self.roundUpUSD = roundUpUSD
        self.feeUSD = feeUSD
        self.fills = fills
    }

    /// Money coming in rather than going out.
    public var isCredit: Bool { kind == .deposit }

    /// "BTC", "ETH", "Mixed", or nil if nothing was bought.
    public var investedSummary: String? {
        let bought = fills.filter { $0.quantity > 0 }
        switch bought.count {
        case 0: return nil
        case 1: return bought[0].asset.ticker
        default: return "Mixed"
        }
    }
}

public enum DCAFrequency: String, Codable, CaseIterable, Sendable, Identifiable {
    case daily, weekly, biweekly, monthly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Monthly"
        }
    }

    /// Phrase that follows "Every", e.g. "Every week".
    public var everyPhrase: String {
        switch self {
        case .daily: return "day"
        case .weekly: return "week"
        case .biweekly: return "2 weeks"
        case .monthly: return "month"
        }
    }

    public func nextDate(after date: Date, calendar: Calendar = .current) -> Date {
        let component: (Calendar.Component, Int)
        switch self {
        case .daily: component = (.day, 1)
        case .weekly: component = (.day, 7)
        case .biweekly: component = (.day, 14)
        case .monthly: component = (.month, 1)
        }
        return calendar.date(byAdding: component.0, value: component.1, to: date) ?? date.addingTimeInterval(86_400)
    }
}

public struct DCASettings: Codable, Hashable, Sendable {
    public var enabled: Bool
    public var amountUSD: Decimal
    public var frequency: DCAFrequency
    public var allocation: Allocation
    /// When the next scheduled buy is due.
    public var nextRun: Date

    public init(enabled: Bool, amountUSD: Decimal, frequency: DCAFrequency, allocation: Allocation, nextRun: Date) {
        self.enabled = enabled
        self.amountUSD = amountUSD
        self.frequency = frequency
        self.allocation = allocation
        self.nextRun = nextRun
    }
}

public struct RoundUpSettings: Codable, Hashable, Sendable {
    public var enabled: Bool
    /// 1x, 2x, 3x ... spare change.
    public var multiplier: Int
    public var allocation: Allocation

    public init(enabled: Bool, multiplier: Int = 1, allocation: Allocation) {
        self.enabled = enabled
        self.multiplier = multiplier
        self.allocation = allocation
    }
}
