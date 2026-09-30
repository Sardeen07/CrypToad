import Foundation

/// Money is always `Decimal`, never `Double`. Binary floating point can't represent
/// values like 0.1 exactly, which produces off-by-a-cent bugs in financial code.
extension Decimal {
    /// Exact decimal from a string literal.
    ///
    /// Use this instead of float literals: `let x: Decimal = 47.89` goes through
    /// `Double` and becomes 47.89000000000000512. `Decimal.exact("47.89")` is exact.
    public static func exact(_ string: String) -> Decimal {
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            preconditionFailure("Invalid decimal literal: \(string)")
        }
        return value
    }

    /// Rounds to `scale` decimal places using the given rounding mode.
    public func rounded(_ scale: Int, _ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    /// Rounds to whole cents, half away from zero.
    public var cents: Decimal { rounded(2) }

    /// Locale-independent dollar string, e.g. "$5.00" or "-$0.75". The app uses
    /// `FormatStyle` for display; this is for error messages and logs.
    public var usdString: String {
        let value = cents
        let negative = value < 0
        let parts = "\(negative ? -value : value)".split(separator: ".", omittingEmptySubsequences: false)
        let whole = String(parts[0])
        let fraction = String(((parts.count > 1 ? String(parts[1]) : "") + "00").prefix(2))
        return (negative ? "-$" : "$") + whole + "." + fraction
    }

    /// Lossy conversion for UI code that needs a `Double` (e.g. chart widths).
    public var doubleValue: Double { NSDecimalNumber(decimal: self).doubleValue }
}
