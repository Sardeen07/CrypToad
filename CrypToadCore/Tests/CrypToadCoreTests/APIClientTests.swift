import XCTest
@testable import CrypToadCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Records requests and replies with canned responses, keyed by "METHOD /path".
private final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: (Int, String)] = [:]
    private(set) var requests: [URLRequest] = []

    func reply(_ method: String, _ path: String, status: Int = 200, _ body: String) {
        lock.lock(); defer { lock.unlock() }
        responses["\(method) \(path)"] = (status, body)
    }

    func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        guard let (status, body) = record(request) else { return (Data(#"{"error":"not_found","detail":"no fake"}"#.utf8), 404) }
        return (Data(body.utf8), status)
    }

    /// Synchronous so the lock is never held across a suspension point.
    private func record(_ request: URLRequest) -> (Int, String)? {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        return responses["\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"]
    }

    var last: URLRequest? { lock.lock(); defer { lock.unlock() }; return requests.last }
}

private func json(_ request: URLRequest?) throws -> [String: Any] {
    let data = try XCTUnwrap(request?.httpBody)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

final class APIClientTests: XCTestCase {
    private var transport: FakeTransport!
    private var api: CrypToadAPI!

    override func setUp() {
        transport = FakeTransport()
        api = CrypToadAPI(baseURL: URL(string: "http://localhost:8000")!, transport: transport)
    }

    // MARK: Accounts

    func testDemoAccountReturnsASessionWithoutSendingAToken() async throws {
        transport.reply("POST", "/api/auth/demo", status: 201, """
        {"token":"tok_123","created":true,"user":{"userId":7,"email":null,"displayName":"Demo Toad","kycStatus":"verified","signInMethod":"demo"}}
        """)
        let session = try await api.createDemoAccount(startingBalance: 1_000)

        XCTAssertEqual(session.token, "tok_123")
        XCTAssertEqual(session.user.userID, 7)
        XCTAssertEqual(session.user.label, "Demo Toad")
        XCTAssertNil(transport.last?.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try json(transport.last)["startingBalance"] as? String, "1000")
    }

    func testAppleSignInSendsTheIdentityTokenAndRawNonce() async throws {
        transport.reply("POST", "/api/auth/apple", """
        {"token":"tok","created":false,"user":{"userId":1,"email":"a@privaterelay.appleid.com","displayName":null,"kycStatus":"verified","signInMethod":"apple"}}
        """)
        _ = try await api.signInWithApple(identityToken: "eyJ.jwt", rawNonce: "nonce-1", fullName: "Ali")
        let body = try json(transport.last)
        XCTAssertEqual(body["identityToken"] as? String, "eyJ.jwt")
        XCTAssertEqual(body["nonce"] as? String, "nonce-1")
        XCTAssertEqual(body["fullName"] as? String, "Ali")
    }

    func testAuthenticatedClientSendsBearerToken() async throws {
        transport.reply("GET", "/api/balances", #"{"balances":{"USDC":"995.15","BTC":"0.0000076","ETH":"0.000088"}}"#)
        let holdings = try await api.authenticated(with: "tok_abc").balances()

        XCTAssertEqual(transport.last?.value(forHTTPHeaderField: "Authorization"), "Bearer tok_abc")
        XCTAssertEqual(holdings[.usdc], Decimal.exact("995.15"))
        XCTAssertEqual(holdings[.btc], Decimal.exact("0.0000076"))
        XCTAssertEqual(holdings[.eth], Decimal.exact("0.000088"))
    }

    // MARK: Activity

    func testActivityMapsOntoTransactionRecords() async throws {
        transport.reply("GET", "/api/activity", """
        {"activity":[
          {"id":"0b7a6e8e-1a3c-4d1e-9d6f-0d5d8f1b2c3a","kind":"purchase","title":"Starbucks","date":"2026-11-11T17:32:41.123456Z",
           "amount":"4.25","roundUp":"0.75","fee":"0.00","source":"card","status":"completed",
           "fills":[{"asset":"BTC","quantity":"0.0000076","price":"50000.00","cost":"0.38"},
                    {"asset":"USDC","quantity":"0.15","price":"1.00","cost":"0.15"}]},
          {"id":"4c3a1d2e-0000-4000-8000-000000000001","kind":"purchase","title":"Uber","date":"2026-11-10T12:00:00Z",
           "amount":"12.40","roundUp":"0.60","fee":"0.00","source":"bank","status":"skipped","fills":[]},
          {"id":"x","kind":"somethingNew","title":"?","date":"2026-11-10T12:00:00+00:00",
           "amount":"1.00","roundUp":"0.00","fee":"0.00","source":null,"status":"completed","fills":[]}
        ]}
        """)
        let records = try await api.activity()

        XCTAssertEqual(records.count, 2, "unknown kinds are dropped, not fatal")
        let coffee = records[0]
        XCTAssertEqual(coffee.id.uuidString.lowercased(), "0b7a6e8e-1a3c-4d1e-9d6f-0d5d8f1b2c3a")
        XCTAssertEqual(coffee.kind, .purchase)
        XCTAssertEqual(coffee.roundUpUSD, Decimal.exact("0.75"))
        XCTAssertEqual(coffee.fills.map(\.asset), [.btc, .usdc])
        XCTAssertEqual(coffee.fills[0].quantity, Decimal.exact("0.0000076"))
        XCTAssertEqual(coffee.date.timeIntervalSince1970, 1_794_418_361.123, accuracy: 0.01)

        let uber = records[1]
        XCTAssertEqual(uber.title, "Uber")
        XCTAssertEqual(uber.roundUpSkipped, true)
        XCTAssertEqual(uber.roundUpUSD, 0)
        XCTAssertNil(coffee.roundUpSkipped)
    }

    // MARK: Trading

    func testQuoteAndTrade() async throws {
        transport.reply("GET", "/api/trade/quote", """
        {"quoteId":"q1","fromAsset":"USDC","toAsset":"BTC","amount":"100.00","fee":"1.00","netAmount":"99.00",
         "rate":"50000.00","estimatedAmount":"0.00198","expiresAt":"2026-11-11T17:33:26.5Z"}
        """)
        transport.reply("POST", "/api/trade", status: 201, #"{"tradeId":"t1","status":"completed"}"#)
        let signedIn = api.authenticated(with: "tok")

        let quote = try await signedIn.quote(spending: 100, on: .btc)
        let query = transport.last?.url?.query ?? ""
        XCTAssertTrue(query.contains("amount=100") && query.contains("from=USDC") && query.contains("to=BTC"), query)
        XCTAssertEqual(quote.id, "q1")
        XCTAssertEqual(quote.quote.quantity, Decimal.exact("0.00198"))
        XCTAssertEqual(quote.quote.netUSD, 99)

        try await signedIn.trade(quoteID: quote.id, idempotencyKey: "key-1")
        XCTAssertEqual(transport.last?.value(forHTTPHeaderField: "Idempotency-Key"), "key-1")
        XCTAssertEqual(try json(transport.last)["quoteId"] as? String, "q1")
    }

    func testInvestSendsAllocationAndIdempotencyKey() async throws {
        transport.reply("POST", "/api/invest", status: 201, """
        {"id":"1b7a6e8e-1a3c-4d1e-9d6f-0d5d8f1b2c3a","kind":"dcaBuy","title":"Auto-Investment (DCA)","date":"2026-11-11T09:00:00Z",
         "amount":"100.00","roundUp":"0.00","fee":"0.00","source":null,"status":"completed","fills":[]}
        """)
        let record = try await api.authenticated(with: "tok").invest(100, allocation: .balanced, idempotencyKey: "dca-1")
        let body = try json(transport.last)
        XCTAssertEqual(body["amount"] as? String, "100")
        XCTAssertEqual((body["allocation"] as? [String: Int])?["btc"], 50)
        XCTAssertEqual(transport.last?.value(forHTTPHeaderField: "Idempotency-Key"), "dca-1")
        XCTAssertEqual(record?.kind, .dcaBuy)
    }

    // MARK: Errors

    func testServerErrorsCarryTheirCode() async {
        transport.reply("POST", "/api/dev/card-purchase", status: 403, #"{"error":"card_frozen","detail":"Your card is frozen."}"#)
        do {
            try await api.simulateCardPurchase(merchant: "Target", amount: 10)
            XCTFail("expected an error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "card_frozen")
            XCTAssertEqual(error.errorDescription, "Your card is frozen.")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    func testUnauthorizedMeansSignInAgain() async {
        transport.reply("GET", "/api/me", status: 401, #"{"detail":"Invalid token"}"#)
        do {
            _ = try await api.me()
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .unauthorized)
        }
    }

    func testValidationErrorsUseFastAPIsMessage() async {
        transport.reply("PUT", "/api/settings", status: 422, #"{"detail":[{"msg":"Input should be less than or equal to 10","loc":["body"]}]}"#)
        do {
            _ = try await api.updateSettings(ServerSettings(roundUps: RoundUpSettings(enabled: true, multiplier: 99, allocation: .balanced), cardFrozen: false))
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual((error as? APIError)?.code, "invalid_request")
        }
    }

    // MARK: Bank

    func testBankSyncSummary() async throws {
        transport.reply("POST", "/api/bank/sync", #"{"status":"HISTORICAL_UPDATE_COMPLETE","added":3,"roundedUp":2,"skipped":0,"totalRoundUp":"1.35"}"#)
        let result = try await api.syncBank()
        XCTAssertEqual(result.totalRoundUp, Decimal.exact("1.35"))
        XCTAssertEqual(result.summary, "Found 3 new purchases and invested $1.35 in spare change.")

        let preparing = BankSyncResult(status: "NOT_READY", added: 0, roundedUp: 0, skipped: 0, totalRoundUp: 0)
        XCTAssertTrue(preparing.isStillPreparing)
    }

    func testBankStatusParsesPlainDates() async throws {
        transport.reply("GET", "/api/bank", """
        {"linked":true,"available":true,"sandbox":true,"institutionName":"First Platypus Bank (Sandbox)",
         "linkedAt":"2026-11-11T17:32:41.5+00:00","lastSyncedAt":null,"roundUpFrom":"2026-11-04"}
        """)
        let status = try await api.bankStatus()
        XCTAssertTrue(status.linked)
        XCTAssertEqual(status.institutionName, "First Platypus Bank (Sandbox)")
        XCTAssertNotNil(status.linkedAt)
        XCTAssertNotNil(APIDecoding.parseDate("2026-11-04"))
    }

    // MARK: Applying server state

    func testApplyingASnapshotKeepsDeviceSettings() {
        var state = PortfolioState.demo()
        state.requireBiometricUnlock = true
        let dca = state.dca
        let snapshot = ServerSnapshot(
            holdings: Holdings([.usdc: 10]),
            transactions: [],
            settings: ServerSettings(roundUps: RoundUpSettings(enabled: false, multiplier: 3, allocation: .stablecoinSaver), cardFrozen: true)
        )
        state.apply(snapshot)

        XCTAssertEqual(state.holdings[.usdc], 10)
        XCTAssertEqual(state.holdings[.btc], 0)
        XCTAssertTrue(state.transactions.isEmpty)
        XCTAssertEqual(state.roundUps.multiplier, 3)
        XCTAssertTrue(state.cardFrozen)
        XCTAssertEqual(state.dca, dca, "DCA schedule stays on the device")
        XCTAssertTrue(state.requireBiometricUnlock)
    }

    func testTakeDueDCARunsAdvancesTheSchedule() {
        let calendar = Calendar(identifier: .gregorian)
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var state = PortfolioState.demo()
        state.dca.enabled = true
        state.dca.frequency = .daily
        state.dca.nextRun = start

        let now = start.addingTimeInterval(2.5 * 86_400)
        let due = state.takeDueDCARuns(now: now, calendar: calendar)
        XCTAssertEqual(due.count, 3)
        XCTAssertEqual(due.first, start)
        XCTAssertGreaterThan(state.dca.nextRun, now)
        XCTAssertTrue(state.takeDueDCARuns(now: now, calendar: calendar).isEmpty, "running twice never repeats a buy")

        state.dca.enabled = false
        state.dca.nextRun = start
        XCTAssertTrue(state.takeDueDCARuns(now: now, calendar: calendar).isEmpty)
    }
}
