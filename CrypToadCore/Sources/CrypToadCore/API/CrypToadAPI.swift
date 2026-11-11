import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends HTTP requests. Swapped for a fake in tests so the client is tested without a server.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, status: Int)
}

extension URLSessionHTTPClient: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (data: Data, status: Int) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: APIError.network(error.localizedDescription))
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (data ?? Data(), status))
            }.resume()
        }
    }
}

public enum APIError: Error, Equatable, LocalizedError {
    /// The server answered with `{"error": code, "detail": message}` (or a bare status).
    case server(status: Int, code: String, detail: String)
    /// The session token is missing, expired, or revoked: sign in again.
    case unauthorized
    case network(String)
    case malformedResponse(String)

    public var errorDescription: String? {
        switch self {
        case let .server(_, _, detail): return detail
        case .unauthorized: return "Your session ended. Please sign in again."
        case .network(let message): return "Can't reach the CrypToad server. \(message)"
        case .malformedResponse(let what): return "Unexpected response from the server (\(what))."
        }
    }

    /// The API error code, e.g. `insufficient_funds` or `quote_expired`.
    public var code: String? {
        if case let .server(_, code, _) = self { return code }
        return nil
    }
}

/// Client for the CrypToad backend (FastAPI). Every call is `async throws`.
///
///     let api = CrypToadAPI(baseURL: URL(string: "http://localhost:8000")!)
///     let session = try await api.createDemoAccount()
///     let signedIn = api.authenticated(with: session.token)
///     let holdings = try await signedIn.balances()
public struct CrypToadAPI: Sendable {
    public let baseURL: URL
    public let token: String?
    private let transport: HTTPTransport

    public init(baseURL: URL, token: String? = nil, transport: HTTPTransport = URLSessionHTTPClient()) {
        self.baseURL = baseURL
        self.token = token
        self.transport = transport
    }

    /// A copy of this client that sends `token` with every request.
    public func authenticated(with token: String) -> CrypToadAPI {
        CrypToadAPI(baseURL: baseURL, token: token, transport: transport)
    }

    // MARK: Meta

    public func info() async throws -> ServerInfo {
        let dto: InfoDTO = try await request("GET", "/api/info")
        return ServerInfo(version: dto.version, demoAccounts: dto.demoAccounts, bankLinking: dto.bankLinking, plaidEnvironment: dto.plaidEnvironment)
    }

    // MARK: Accounts

    /// Exchanges a Sign in with Apple identity token for a CrypToad session.
    /// `rawNonce` is the value whose SHA-256 was set on the Apple request.
    public func signInWithApple(identityToken: String, rawNonce: String?, fullName: String?) async throws -> AuthSession {
        var body: [String: Any] = ["identityToken": identityToken]
        if let rawNonce { body["nonce"] = rawNonce }
        if let fullName, !fullName.isEmpty { body["fullName"] = fullName }
        let dto: SessionDTO = try await request("POST", "/api/auth/apple", body: body)
        return dto.model
    }

    /// A throwaway account with simulated USDC (demo servers only).
    public func createDemoAccount(startingBalance: Decimal = 1_000) async throws -> AuthSession {
        let dto: SessionDTO = try await request("POST", "/api/auth/demo", body: ["startingBalance": startingBalance.apiString])
        return dto.model
    }

    public func me() async throws -> AccountUser {
        let dto: UserDTO = try await request("GET", "/api/me")
        return dto.model
    }

    public func logout() async throws {
        try await send("POST", "/api/auth/logout")
    }

    public func deleteAccount() async throws {
        try await send("DELETE", "/api/me")
    }

    // MARK: Portfolio

    public func balances() async throws -> Holdings {
        let dto: BalancesDTO = try await request("GET", "/api/balances")
        var holdings = Holdings()
        for (ticker, amount) in dto.balances {
            guard let asset = Asset(ticker: ticker) else { continue }
            holdings[asset] = try Decimal(api: amount)
        }
        return holdings
    }

    public func activity(limit: Int = 200) async throws -> [TransactionRecord] {
        let dto: ActivityListDTO = try await request("GET", "/api/activity", query: ["limit": "\(limit)"])
        return try dto.activity.compactMap { try $0.record() }
    }

    public func settings() async throws -> ServerSettings {
        let dto: SettingsDTO = try await request("GET", "/api/settings")
        return dto.model
    }

    @discardableResult
    public func updateSettings(_ settings: ServerSettings) async throws -> ServerSettings {
        let dto: SettingsDTO = try await request("PUT", "/api/settings", body: SettingsDTO(settings).json)
        return dto.model
    }

    /// Balances, history, and settings fetched concurrently.
    public func snapshot() async throws -> ServerSnapshot {
        async let holdings = balances()
        async let transactions = activity()
        async let settings = settings()
        return try await ServerSnapshot(holdings: holdings, transactions: transactions, settings: settings)
    }

    // MARK: Money movement

    public func quote(spending usd: Decimal, on asset: Asset) async throws -> ServerQuote {
        let dto: QuoteDTO = try await request(
            "GET", "/api/trade/quote",
            query: ["from": "USDC", "to": asset.ticker, "amount": usd.apiString]
        )
        return try dto.model()
    }

    /// Executes a quote. Send the same `idempotencyKey` when retrying so the trade can never happen twice.
    public func trade(quoteID: String, idempotencyKey: String) async throws {
        let _: IgnoredDTO = try await request("POST", "/api/trade", body: ["quoteId": quoteID], idempotencyKey: idempotencyKey)
    }

    /// One DCA buy, split by `allocation`.
    @discardableResult
    public func invest(_ usd: Decimal, allocation: Allocation, idempotencyKey: String) async throws -> TransactionRecord? {
        let dto: ActivityDTO = try await request(
            "POST", "/api/invest",
            body: ["amount": usd.apiString, "allocation": AllocationDTO(allocation).json],
            idempotencyKey: idempotencyKey
        )
        return try dto.record()
    }

    /// Simulates a card swipe (demo servers only; in production the card network calls the server).
    @discardableResult
    public func simulateCardPurchase(merchant: String, amount: Decimal) async throws -> TransactionRecord? {
        let dto: ActivityDTO = try await request("POST", "/api/dev/card-purchase", body: ["merchant": merchant, "amount": amount.apiString])
        return try dto.record()
    }

    /// Simulates a paycheck arriving as USDC (demo servers only).
    public func simulateDeposit(_ amount: Decimal) async throws {
        let _: IgnoredDTO = try await request("POST", "/api/dev/deposit", body: ["amount": amount.apiString])
    }

    // MARK: Bank (Plaid)

    public func bankStatus() async throws -> BankStatus {
        let dto: BankStatusDTO = try await request("GET", "/api/bank")
        return dto.model
    }

    /// Sandbox only: links Plaid's test bank without the Link UI.
    public func linkSandboxBank() async throws -> BankStatus {
        let dto: BankStatusDTO = try await request("POST", "/api/bank/sandbox-link")
        return dto.model
    }

    /// For the Plaid Link SDK: returns a `link_token` to open Link with.
    public func bankLinkToken() async throws -> String {
        let dto: LinkTokenDTO = try await request("POST", "/api/bank/link-token")
        return dto.linkToken
    }

    /// Finishes Plaid Link with the `public_token` it returned.
    public func exchangeBankToken(_ publicToken: String, institutionName: String?) async throws -> BankStatus {
        var body: [String: Any] = ["publicToken": publicToken]
        if let institutionName { body["institutionName"] = institutionName }
        let dto: BankStatusDTO = try await request("POST", "/api/bank/exchange", body: body)
        return dto.model
    }

    public func syncBank() async throws -> BankSyncResult {
        let dto: BankSyncDTO = try await request("POST", "/api/bank/sync")
        return BankSyncResult(
            status: dto.status, added: dto.added, roundedUp: dto.roundedUp, skipped: dto.skipped,
            totalRoundUp: try Decimal(api: dto.totalRoundUp)
        )
    }

    public func unlinkBank() async throws {
        try await send("DELETE", "/api/bank")
    }

    // MARK: Plumbing

    /// Builds the URLRequest for an endpoint. Internal so tests can inspect it.
    func makeRequest(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        idempotencyKey: String? = nil
    ) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw APIError.malformedResponse("bad URL for \(path)") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let idempotencyKey { request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, status) = try await transport.send(request)
        switch status {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        default:
            if let error = try? JSONDecoder().decode(ErrorDTO.self, from: data) {
                throw APIError.server(status: status, code: error.error, detail: error.detail)
            }
            if let validation = try? JSONDecoder().decode(ValidationErrorDTO.self, from: data), let first = validation.detail.first {
                throw APIError.server(status: status, code: "invalid_request", detail: first.msg)
            }
            throw APIError.server(status: status, code: "http_\(status)", detail: "The server returned HTTP \(status).")
        }
    }

    private func request<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [String: String] = [:],
        body: [String: Any]? = nil,
        idempotencyKey: String? = nil
    ) async throws -> T {
        let data = try await perform(makeRequest(method, path, query: query, body: body, idempotencyKey: idempotencyKey))
        do {
            return try APIDecoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.malformedResponse("\(T.self)")
        }
    }

    private func send(_ method: String, _ path: String) async throws {
        _ = try await perform(makeRequest(method, path))
    }
}

// MARK: - Decoding helpers

extension Decimal {
    /// Parses an API decimal string such as "0.00198" exactly.
    init(api string: String) throws {
        guard let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else {
            throw APIError.malformedResponse("amount \(string)")
        }
        self = value
    }

    /// Locale-independent decimal string for request bodies, e.g. "4.25".
    var apiString: String { "\(self)" }
}

extension Asset {
    /// From an API ticker such as "BTC".
    init?(ticker: String) {
        self.init(rawValue: ticker.lowercased())
    }
}

enum APIDecoding {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognized date \(string)")
            }
            return date
        }
        return decoder
    }

    /// Accepts "2026-11-11T17:32:41.123456Z", "...+00:00", without fractions, and plain "2026-11-11".
    static func parseDate(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = withFraction.date(from: string) ?? plain.date(from: string) { return date }

        // Python sends microseconds; trim the fraction to milliseconds for ISO8601DateFormatter.
        if let dot = string.firstIndex(of: ".") {
            let afterDot = string[string.index(after: dot)...]
            let digits = afterDot.prefix(while: \.isNumber)
            let zone = afterDot.dropFirst(digits.count)
            let trimmed = string[..<dot] + "." + digits.prefix(3) + zone
            if let date = withFraction.date(from: String(trimmed)) { return date }
        }
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        return day.date(from: string)
    }
}

// MARK: - Wire formats (camelCase JSON, money as strings)

private struct ErrorDTO: Decodable {
    var error: String
    var detail: String
}

private struct ValidationErrorDTO: Decodable {
    struct Item: Decodable { var msg: String }
    var detail: [Item]
}

private struct IgnoredDTO: Decodable {}

private struct InfoDTO: Decodable {
    var version: String
    var demoAccounts: Bool
    var bankLinking: Bool
    var plaidEnvironment: String?
}

private struct UserDTO: Decodable {
    var userId: Int
    var email: String?
    var displayName: String?
    var kycStatus: String
    var signInMethod: String

    var model: AccountUser {
        AccountUser(userID: userId, email: email, displayName: displayName, kycStatus: kycStatus, signInMethod: signInMethod)
    }
}

private struct SessionDTO: Decodable {
    var token: String
    var user: UserDTO
    var created: Bool

    var model: AuthSession { AuthSession(token: token, user: user.model, created: created) }
}

private struct BalancesDTO: Decodable {
    var balances: [String: String]
}

private struct AllocationDTO: Codable {
    var btc: Int
    var eth: Int
    var usdc: Int

    init(_ allocation: Allocation) {
        btc = allocation.btc
        eth = allocation.eth
        usdc = allocation.usdc
    }

    var model: Allocation { Allocation(btc: btc, eth: eth, usdc: usdc) }
    var json: [String: Any] { ["btc": btc, "eth": eth, "usdc": usdc] }
}

private struct SettingsDTO: Decodable {
    struct RoundUps: Decodable {
        var enabled: Bool
        var multiplier: Int
        var allocation: AllocationDTO
    }

    var roundUps: RoundUps
    var cardFrozen: Bool

    init(_ settings: ServerSettings) {
        roundUps = RoundUps(
            enabled: settings.roundUps.enabled,
            multiplier: settings.roundUps.multiplier,
            allocation: AllocationDTO(settings.roundUps.allocation)
        )
        cardFrozen = settings.cardFrozen
    }

    var model: ServerSettings {
        ServerSettings(
            roundUps: RoundUpSettings(enabled: roundUps.enabled, multiplier: roundUps.multiplier, allocation: roundUps.allocation.model),
            cardFrozen: cardFrozen
        )
    }

    var json: [String: Any] {
        [
            "roundUps": ["enabled": roundUps.enabled, "multiplier": roundUps.multiplier, "allocation": roundUps.allocation.json],
            "cardFrozen": cardFrozen
        ]
    }
}

private struct FillDTO: Decodable {
    var asset: String
    var quantity: String
    var price: String
    var cost: String
}

private struct ActivityDTO: Decodable {
    var id: String
    var kind: String
    var title: String
    var date: Date
    var amount: String
    var roundUp: String
    var fee: String
    var fills: [FillDTO]
    var source: String?
    var status: String

    /// `nil` for kinds this version of the app doesn't know about.
    func record() throws -> TransactionRecord? {
        guard let kind = TransactionRecord.Kind(rawValue: kind) else { return nil }
        let skipped = status == "skipped"
        let fills: [Fill] = try self.fills.compactMap { dto in
            guard let asset = Asset(ticker: dto.asset) else { return nil }
            return Fill(
                asset: asset,
                quantity: try Decimal(api: dto.quantity),
                priceUSD: try Decimal(api: dto.price),
                costUSD: try Decimal(api: dto.cost)
            )
        }
        return TransactionRecord(
            id: UUID(uuidString: id) ?? UUID(),
            kind: kind,
            date: date,
            title: title,
            amountUSD: try Decimal(api: amount),
            roundUpUSD: skipped ? 0 : try Decimal(api: roundUp),
            feeUSD: try Decimal(api: fee),
            fills: skipped ? [] : fills,
            roundUpSkipped: skipped ? true : nil
        )
    }
}

private struct ActivityListDTO: Decodable {
    var activity: [ActivityDTO]
}

private struct QuoteDTO: Decodable {
    var quoteId: String
    var toAsset: String
    var amount: String
    var fee: String
    var rate: String
    var estimatedAmount: String
    var expiresAt: Date

    func model() throws -> ServerQuote {
        guard let asset = Asset(ticker: toAsset) else { throw APIError.malformedResponse("asset \(toAsset)") }
        let quote = TradeQuote(
            asset: asset,
            spendUSD: try Decimal(api: amount),
            feeUSD: try Decimal(api: fee),
            priceUSD: try Decimal(api: rate),
            quantity: try Decimal(api: estimatedAmount)
        )
        return ServerQuote(id: quoteId, expiresAt: expiresAt, quote: quote)
    }
}

private struct BankStatusDTO: Decodable {
    var linked: Bool
    var available: Bool
    var sandbox: Bool
    var institutionName: String?
    var linkedAt: Date?
    var lastSyncedAt: Date?

    var model: BankStatus {
        BankStatus(linked: linked, available: available, sandbox: sandbox, institutionName: institutionName, linkedAt: linkedAt, lastSyncedAt: lastSyncedAt)
    }
}

private struct LinkTokenDTO: Decodable {
    var linkToken: String
}

private struct BankSyncDTO: Decodable {
    var status: String
    var added: Int
    var roundedUp: Int
    var skipped: Int
    var totalRoundUp: String
}
