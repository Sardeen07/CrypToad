import Foundation

/// How an investment is split across assets, in whole percentages that always total 100.
public struct Allocation: Codable, Hashable, Sendable {
    public var btc: Int
    public var eth: Int
    public var usdc: Int

    public init(btc: Int, eth: Int, usdc: Int) {
        self.btc = btc
        self.eth = eth
        self.usdc = usdc
    }

    public subscript(asset: Asset) -> Int {
        get {
            switch asset {
            case .btc: return btc
            case .eth: return eth
            case .usdc: return usdc
            }
        }
        set {
            switch asset {
            case .btc: btc = newValue
            case .eth: eth = newValue
            case .usdc: usdc = newValue
            }
        }
    }

    public var total: Int { btc + eth + usdc }

    public var isValid: Bool {
        total == 100 && Asset.allCases.allSatisfy { self[$0] >= 0 }
    }

    /// Short label such as "50% BTC · 30% ETH · 20% USDC" (zero weights omitted).
    public var summary: String {
        Asset.allCases
            .filter { self[$0] > 0 }
            .map { "\(self[$0])% \($0.ticker)" }
            .joined(separator: " · ")
    }

    // MARK: Presets

    public static let balanced = Allocation(btc: 50, eth: 30, usdc: 20)
    public static let aggressiveBitcoin = Allocation(btc: 80, eth: 15, usdc: 5)
    public static let stablecoinSaver = Allocation(btc: 10, eth: 10, usdc: 80)

    /// Name of the matching preset, if any.
    public var presetName: String? {
        switch self {
        case .balanced: return "Balanced Growth"
        case .aggressiveBitcoin: return "Aggressive Bitcoin"
        case .stablecoinSaver: return "Stablecoin Saver"
        default: return nil
        }
    }

    public static let presets: [AllocationPreset] = [
        AllocationPreset(name: "Balanced Growth", allocation: .balanced),
        AllocationPreset(name: "Aggressive Bitcoin", allocation: .aggressiveBitcoin),
        AllocationPreset(name: "Stablecoin Saver", allocation: .stablecoinSaver)
    ]

    // MARK: Splitting money

    /// Splits a dollar amount across assets by weight.
    ///
    /// Each share is rounded *down* to the cent, then any leftover cents go to the
    /// asset with the largest weight, so the shares always add up to exactly `amount`
    /// (rounded to cents). No money is created or lost to rounding.
    public func split(_ amount: Decimal) -> [Asset: Decimal] {
        let total = amount.cents
        var shares: [Asset: Decimal] = [:]
        var assigned: Decimal = 0

        for asset in Asset.allCases {
            let share = (total * Decimal(self[asset]) / 100).rounded(2, .down)
            shares[asset] = share
            assigned += share
        }

        let leftover = total - assigned
        if leftover != 0, let largest = Asset.allCases.max(by: { self[$0] < self[$1] }) {
            shares[largest, default: 0] += leftover
        }
        return shares
    }

    // MARK: Editing

    /// Returns a copy with `asset` set to `newValue` (clamped to 0...100) and the
    /// other assets scaled proportionally so the total stays at exactly 100.
    ///
    /// This is what backs the allocation sliders: dragging one slider never lets
    /// the total drift away from 100%.
    public func adjusting(_ asset: Asset, to newValue: Int) -> Allocation {
        let target = min(max(newValue, 0), 100)
        let others = Asset.allCases.filter { $0 != asset }
        let remaining = 100 - target
        let othersTotal = others.reduce(0) { $0 + self[$1] }

        var result = self
        result[asset] = target

        if othersTotal == 0 {
            // Nothing to scale from: share the remainder evenly.
            let each = remaining / others.count
            for other in others { result[other] = each }
            result[others[0]] += remaining - each * others.count
        } else {
            var distributed = 0
            for other in others {
                let scaled = remaining * self[other] / othersTotal
                result[other] = scaled
                distributed += scaled
            }
            // Integer division can leave a point or two over; give it to the biggest remaining weight.
            let leftover = remaining - distributed
            if leftover != 0, let biggest = others.max(by: { self[$0] < self[$1] }) {
                result[biggest] += leftover
            }
        }
        return result
    }
}

/// A named allocation template (the "pre-built DCA templates" from the product spec).
public struct AllocationPreset: Identifiable, Hashable, Sendable {
    public let name: String
    public let allocation: Allocation
    public var id: String { name }

    public init(name: String, allocation: Allocation) {
        self.name = name
        self.allocation = allocation
    }
}
