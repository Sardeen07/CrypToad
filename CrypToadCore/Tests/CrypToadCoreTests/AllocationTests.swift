import XCTest
@testable import CrypToadCore

final class AllocationTests: XCTestCase {
    func testPresetsAreValid() {
        for preset in Allocation.presets {
            XCTAssertTrue(preset.allocation.isValid, preset.name)
            XCTAssertEqual(preset.allocation.presetName, preset.name)
        }
        XCTAssertNil(Allocation(btc: 34, eth: 33, usdc: 33).presetName)
    }

    func testInvalidAllocations() {
        XCTAssertFalse(Allocation(btc: 50, eth: 30, usdc: 10).isValid)
        XCTAssertFalse(Allocation(btc: 120, eth: -20, usdc: 0).isValid)
    }

    func testSummaryOmitsZeroWeights() {
        XCTAssertEqual(Allocation.balanced.summary, "50% BTC · 30% ETH · 20% USDC")
        XCTAssertEqual(Allocation(btc: 100, eth: 0, usdc: 0).summary, "100% BTC")
    }

    func testSplitGivesLeftoverCentToLargestWeight() {
        // 0.75 × 50/30/20 = 0.375 / 0.225 / 0.15 → rounded down 0.37 / 0.22 / 0.15 = 0.74.
        // The missing cent goes to BTC (largest weight).
        let shares = Allocation.balanced.split(D("0.75"))
        XCTAssertEqual(shares[.btc], D("0.38"))
        XCTAssertEqual(shares[.eth], D("0.22"))
        XCTAssertEqual(shares[.usdc], D("0.15"))
    }

    func testSplitNeverCreatesOrLosesMoney() {
        let allocations = Allocation.presets.map(\.allocation) + [
            Allocation(btc: 33, eth: 33, usdc: 34),
            Allocation(btc: 1, eth: 1, usdc: 98),
            Allocation(btc: 100, eth: 0, usdc: 0)
        ]
        for allocation in allocations {
            for cents in stride(from: 1, through: 25_000, by: 7) {
                let amount = Decimal(cents) / 100
                let shares = allocation.split(amount)
                let sum = shares.values.reduce(0, +)
                XCTAssertEqual(sum, amount, "\(allocation.summary) split of \(amount)")
                XCTAssertTrue(shares.values.allSatisfy { $0 >= 0 })
            }
        }
    }

    func testAdjustingScalesOthersProportionally() {
        let result = Allocation.balanced.adjusting(.btc, to: 70)
        XCTAssertEqual(result, Allocation(btc: 70, eth: 18, usdc: 12))
    }

    func testAdjustingToHundredZeroesOthers() {
        XCTAssertEqual(Allocation.balanced.adjusting(.eth, to: 100), Allocation(btc: 0, eth: 100, usdc: 0))
    }

    func testAdjustingFromAllInSharesRemainderEvenly() {
        let allIn = Allocation(btc: 100, eth: 0, usdc: 0)
        XCTAssertEqual(allIn.adjusting(.btc, to: 40), Allocation(btc: 40, eth: 30, usdc: 30))
        XCTAssertEqual(allIn.adjusting(.btc, to: 41), Allocation(btc: 41, eth: 30, usdc: 29))
    }

    func testAdjustingClampsOutOfRangeValues() {
        XCTAssertEqual(Allocation.balanced.adjusting(.usdc, to: 150).usdc, 100)
        XCTAssertEqual(Allocation.balanced.adjusting(.usdc, to: -10).usdc, 0)
    }

    func testAdjustingAlwaysTotalsHundred() {
        var allocation = Allocation.balanced
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<2_000 {
            let asset = Asset.allCases.randomElement(using: &generator)!
            let value = Int.random(in: -20...130, using: &generator)
            allocation = allocation.adjusting(asset, to: value)
            XCTAssertTrue(allocation.isValid, "\(allocation)")
        }
    }
}

/// Deterministic RNG so the fuzz test is reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
