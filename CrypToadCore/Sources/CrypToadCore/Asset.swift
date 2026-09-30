import Foundation

/// The assets CrypToad supports.
public enum Asset: String, CaseIterable, Codable, CodingKeyRepresentable, Hashable, Sendable, Identifiable {
    case btc
    case eth
    case usdc

    public var id: String { rawValue }

    /// Ticker symbol, e.g. "BTC".
    public var ticker: String { rawValue.uppercased() }

    public var displayName: String {
        switch self {
        case .btc: return "Bitcoin"
        case .eth: return "Ethereum"
        case .usdc: return "USD Coin"
        }
    }

    /// Single-character glyph used in the UI.
    public var glyph: String {
        switch self {
        case .btc: return "₿"
        case .eth: return "Ξ"
        case .usdc: return "$"
        }
    }

    /// CoinGecko API identifier.
    public var coinGeckoID: String {
        switch self {
        case .btc: return "bitcoin"
        case .eth: return "ethereum"
        case .usdc: return "usd-coin"
        }
    }

    public var isStablecoin: Bool { self == .usdc }

    /// Decimal places balances are tracked to.
    /// BTC uses 8 (1 satoshi). ETH is capped at 8 for readability. USDC uses 6, matching the token contract.
    public var precision: Int {
        switch self {
        case .btc, .eth: return 8
        case .usdc: return 6
        }
    }

    public init?(coinGeckoID: String) {
        guard let match = Asset.allCases.first(where: { $0.coinGeckoID == coinGeckoID }) else { return nil }
        self = match
    }
}
