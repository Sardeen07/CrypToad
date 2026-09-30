import Foundation

/// Round-up ("spare change") math.
public enum RoundUp {
    /// The amount needed to bring a purchase up to the next whole dollar.
    ///
    ///     spareChange(for: 4.25)  // 0.75
    ///     spareChange(for: 5.00)  // 0.00 — whole-dollar purchases don't round up
    ///
    /// The purchase is first rounded to cents so sub-cent inputs can't produce sub-cent round-ups.
    public static func spareChange(for amount: Decimal) -> Decimal {
        guard amount > 0 else { return 0 }
        let price = amount.cents
        let nextDollar = price.rounded(0, .up)
        return nextDollar - price
    }

    /// Spare change with a multiplier applied (e.g. "2x round-ups" invests $1.50 on a $4.25 coffee).
    public static func spareChange(for amount: Decimal, multiplier: Int) -> Decimal {
        spareChange(for: amount) * Decimal(max(multiplier, 0))
    }
}
