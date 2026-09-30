import Foundation
import CrypToadCore

/// Display formatting. All money stays `Decimal` until the moment it becomes text.
extension Decimal {
    /// "$1,234.56"
    var usd: String {
        formatted(.currency(code: "USD"))
    }

    /// "+$12.34" / "-$12.34"
    var signedUSD: String {
        (self >= 0 ? "+" : "-") + (self < 0 ? -self : self).usd
    }

    /// "+2.14%" / "-1.05%"
    var signedPercent: String {
        let magnitude = (self < 0 ? -self : self).formatted(.number.precision(.fractionLength(2)))
        return (self >= 0 ? "+" : "-") + magnitude + "%"
    }

    /// Crypto quantity with up to `maxDigits` decimals and no trailing zeros, e.g. "0.0234".
    func quantity(maxDigits: Int = 8) -> String {
        formatted(.number.precision(.fractionLength(0...maxDigits)))
    }
}

extension Asset {
    /// Quantity formatted for this asset, e.g. "0.0234 BTC" or "1,234.56 USDC".
    func format(_ quantity: Decimal) -> String {
        let digits = isStablecoin ? 2 : precision
        return "\(quantity.quantity(maxDigits: digits)) \(ticker)"
    }
}
