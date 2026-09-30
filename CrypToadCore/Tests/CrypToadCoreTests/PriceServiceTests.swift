import XCTest
@testable import CrypToadCore

struct MockHTTPClient: HTTPClient {
    var data: Data
    var status: Int
    func get(_ url: URL) async throws -> (data: Data, status: Int) { (data, status) }
}

final class PriceServiceTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "coingecko-simple-price", withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    func testRequestURL() {
        let url = CoinGeckoPriceService.requestURL.absoluteString
        XCTAssertTrue(url.hasPrefix("https://api.coingecko.com/api/v3/simple/price?"))
        XCTAssertTrue(url.contains("ids=bitcoin,ethereum,usd-coin"))
        XCTAssertTrue(url.contains("vs_currencies=usd"))
        XCTAssertTrue(url.contains("include_24hr_change=true"))
    }

    func testDecodesPricesAsExactDecimals() throws {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let snapshot = try CoinGeckoPriceService.decode(try fixture(), fetchedAt: date)

        XCTAssertEqual(snapshot.price(of: .btc), D("92340.12"))
        XCTAssertEqual(snapshot.price(of: .eth), D("3120.5"))
        XCTAssertEqual(snapshot.price(of: .usdc), D("0.9999"))
        XCTAssertEqual(snapshot.change24h(of: .btc), D("1.84"))
        XCTAssertEqual(snapshot.change24h(of: .eth), D("-2.37"))
        XCTAssertEqual(snapshot.fetchedAt, date)
        XCTAssertFalse(snapshot.isPlaceholder)
    }

    func testMissingAssetThrows() {
        let json = Data(#"{"bitcoin":{"usd":1},"ethereum":{"usd":2}}"#.utf8)
        XCTAssertThrowsError(try CoinGeckoPriceService.decode(json, fetchedAt: Date())) { error in
            XCTAssertEqual(error as? PriceServiceError, .missingAsset(.usdc))
        }
    }

    func testMalformedResponseThrows() {
        XCTAssertThrowsError(try CoinGeckoPriceService.decode(Data("not json".utf8), fetchedAt: Date())) { error in
            XCTAssertEqual(error as? PriceServiceError, .malformedResponse)
        }
    }

    func testFetchSuccess() async throws {
        let data = try fixture()
        let service = CoinGeckoPriceService(client: MockHTTPClient(data: data, status: 200))
        let snapshot = try await service.fetchPrices()
        XCTAssertEqual(snapshot.price(of: .btc), D("92340.12"))
    }

    func testRateLimitIsReported() async throws {
        let service = CoinGeckoPriceService(client: MockHTTPClient(data: Data(), status: 429))
        do {
            _ = try await service.fetchPrices()
            XCTFail("Expected rate-limit error")
        } catch {
            XCTAssertEqual(error as? PriceServiceError, .rateLimited)
        }
    }

    func testServerErrorIsReported() async throws {
        let service = CoinGeckoPriceService(client: MockHTTPClient(data: Data(), status: 503))
        do {
            _ = try await service.fetchPrices()
            XCTFail("Expected server error")
        } catch {
            XCTAssertEqual(error as? PriceServiceError, .badStatus(503))
        }
    }

    func testPlaceholderIsAlwaysStale() {
        XCTAssertTrue(PriceSnapshot.placeholder.isStale())
        let fresh = PriceSnapshot(quotes: [:], fetchedAt: Date())
        XCTAssertFalse(fresh.isStale())
        XCTAssertTrue(fresh.isStale(now: Date().addingTimeInterval(600)))
    }

    func testUSDCFallsBackToOneDollar() {
        let snapshot = PriceSnapshot(quotes: [:], fetchedAt: Date())
        XCTAssertEqual(snapshot.price(of: .usdc), 1)
        XCTAssertNil(snapshot.price(of: .btc))
    }
}
