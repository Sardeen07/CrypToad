import XCTest
@testable import CrypToadCore

/// Shorthand for exact decimals in tests.
func D(_ string: String) -> Decimal { Decimal.exact(string) }

final class RoundUpTests: XCTestCase {
    func testRoundsUpToNextDollar() {
        XCTAssertEqual(RoundUp.spareChange(for: D("4.25")), D("0.75"))
        XCTAssertEqual(RoundUp.spareChange(for: D("47.89")), D("0.11"))
        XCTAssertEqual(RoundUp.spareChange(for: D("0.01")), D("0.99"))
    }

    func testWholeDollarPurchaseHasNoRoundUp() {
        XCTAssertEqual(RoundUp.spareChange(for: 5), 0)
        XCTAssertEqual(RoundUp.spareChange(for: D("5.00")), 0)
    }

    func testZeroAndNegativeAmountsHaveNoRoundUp() {
        XCTAssertEqual(RoundUp.spareChange(for: 0), 0)
        XCTAssertEqual(RoundUp.spareChange(for: D("-3.20")), 0)
    }

    func testSubCentAmountsAreRoundedToCentsFirst() {
        // $4.999 is charged as $5.00, so there is nothing to round up.
        XCTAssertEqual(RoundUp.spareChange(for: D("4.999")), 0)
        XCTAssertEqual(RoundUp.spareChange(for: D("4.244")), D("0.76"))
    }

    func testMultiplier() {
        XCTAssertEqual(RoundUp.spareChange(for: D("4.25"), multiplier: 2), D("1.50"))
        XCTAssertEqual(RoundUp.spareChange(for: D("4.25"), multiplier: 0), 0)
    }

    func testRoundUpIsAlwaysUnderOneDollar() {
        for cents in 1...5_000 {
            let amount = Decimal(cents) / 100
            let spare = RoundUp.spareChange(for: amount)
            XCTAssertGreaterThanOrEqual(spare, 0)
            XCTAssertLessThan(spare, 1)
            // Purchase + spare change always lands on a whole dollar.
            XCTAssertEqual((amount + spare).rounded(0), amount + spare)
        }
    }
}

final class MoneyTests: XCTestCase {
    func testExactAvoidsFloatingPointDrift() {
        XCTAssertEqual(D("47.89").description, "47.89")
        XCTAssertEqual(D("0.1") + D("0.2"), D("0.3"))
    }

    func testRounding() {
        XCTAssertEqual(D("1.005").cents, D("1.01"))
        XCTAssertEqual(D("1.239").rounded(2, .down), D("1.23"))
        XCTAssertEqual(D("1.231").rounded(2, .up), D("1.24"))
    }

    func testUSDString() {
        XCTAssertEqual(D("5").usdString, "$5.00")
        XCTAssertEqual(D("0.75").usdString, "$0.75")
        XCTAssertEqual(D("1234.5").usdString, "$1234.50")
        XCTAssertEqual(D("-0.75").usdString, "-$0.75")
    }
}
