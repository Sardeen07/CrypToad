import Foundation

/// A USD price for one asset, with its 24-hour percentage change when known.
public struct PriceQuote: Codable, Hashable, Sendable {
    public var usd: Decimal
    /// Percent change over 24 hours, e.g. `2.5` means +2.5%.
    public var change24h: Decimal?

    public init(usd: Decimal, change24h: Decimal? = nil) {
        self.usd = usd
        self.change24h = change24h
    }
}

/// Prices for every asset at a point in time.
public struct PriceSnapshot: Codable, Hashable, Sendable {
    public var quotes: [Asset: PriceQuote]
    public var fetchedAt: Date
    /// `true` for the built-in placeholder prices used before the first successful fetch.
    public var isPlaceholder: Bool

    public init(quotes: [Asset: PriceQuote], fetchedAt: Date, isPlaceholder: Bool = false) {
        self.quotes = quotes
        self.fetchedAt = fetchedAt
        self.isPlaceholder = isPlaceholder
    }

    /// USD price of `asset`, or `nil` if unknown. USDC falls back to $1.
    public func price(of asset: Asset) -> Decimal? {
        if let quote = quotes[asset], quote.usd > 0 { return quote.usd }
        return asset.isStablecoin ? 1 : nil
    }

    public func change24h(of asset: Asset) -> Decimal? {
        quotes[asset]?.change24h
    }

    public func isStale(now: Date = Date(), maxAge: TimeInterval = 5 * 60) -> Bool {
        isPlaceholder || now.timeIntervalSince(fetchedAt) > maxAge
    }

    /// Rough prices used only until the first live fetch succeeds (e.g. offline first launch).
    public static let placeholder = PriceSnapshot(
        quotes: [
            .btc: PriceQuote(usd: 92_340),
            .eth: PriceQuote(usd: 3_120),
            .usdc: PriceQuote(usd: 1)
        ],
        fetchedAt: Date(timeIntervalSince1970: 0),
        isPlaceholder: true
    )
}

/// Anything that can produce current prices.
public protocol PriceService: Sendable {
    func fetchPrices() async throws -> PriceSnapshot
}

/// Returns a fixed snapshot. Used for SwiftUI previews and tests.
public struct StaticPriceService: PriceService {
    public let snapshot: PriceSnapshot
    public init(snapshot: PriceSnapshot) { self.snapshot = snapshot }
    public func fetchPrices() async throws -> PriceSnapshot { snapshot }
}
