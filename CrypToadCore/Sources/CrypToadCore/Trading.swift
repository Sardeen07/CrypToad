import Foundation

/// A priced USDC → asset conversion, shown to the user before they confirm.
public struct TradeQuote: Hashable, Sendable {
    public var asset: Asset
    /// Dollars the user is spending, including the fee.
    public var spendUSD: Decimal
    public var feeUSD: Decimal
    public var priceUSD: Decimal
    /// Amount of `asset` received after the fee.
    public var quantity: Decimal

    /// Dollars actually converted (spend minus fee).
    public var netUSD: Decimal { spendUSD - feeUSD }
}

public enum Trading {
    /// Conversion fee for manual trades (1%, the middle of the 0.5–1.5% range in the API spec).
    public static let manualTradeFeeRate = Decimal.exact("0.01")

    /// Smallest trade accepted.
    public static let minimumTradeUSD: Decimal = 1

    /// Builds a quote for spending `usd` of USDC on `asset`.
    public static func quote(
        spending usd: Decimal,
        on asset: Asset,
        prices: PriceSnapshot,
        feeRate: Decimal = manualTradeFeeRate
    ) throws -> TradeQuote {
        let spend = usd.cents
        guard spend > 0 else { throw PortfolioError.invalidAmount }
        guard let price = prices.price(of: asset) else { throw PortfolioError.missingPrice(asset) }

        let fee = (spend * feeRate).rounded(2, .up)
        let quantity = ((spend - fee) / price).rounded(asset.precision, .down)
        return TradeQuote(asset: asset, spendUSD: spend, feeUSD: fee, priceUSD: price, quantity: quantity)
    }
}

public enum PortfolioError: Error, Equatable, LocalizedError {
    case cardFrozen
    case insufficientFunds(needed: Decimal, available: Decimal)
    case invalidAmount
    case invalidAllocation
    case missingPrice(Asset)
    case unsupportedAsset(Asset)

    public var errorDescription: String? {
        switch self {
        case .cardFrozen:
            return "Your card is frozen. Unfreeze it in the Card tab to make purchases."
        case let .insufficientFunds(needed, available):
            return "Not enough USDC. Needed \(needed.usdString), available \(available.usdString)."
        case .invalidAmount:
            return "Enter an amount greater than zero."
        case .invalidAllocation:
            return "Allocation percentages must add up to 100%."
        case .missingPrice(let asset):
            return "No price available for \(asset.ticker) yet."
        case .unsupportedAsset(let asset):
            return "\(asset.ticker) can't be bought with USDC."
        }
    }
}
