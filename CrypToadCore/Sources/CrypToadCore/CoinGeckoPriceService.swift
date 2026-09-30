import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PriceServiceError: Error, Equatable, LocalizedError {
    case rateLimited
    case badStatus(Int)
    case missingAsset(Asset)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .rateLimited: return "Price service is rate-limiting requests. Try again in a minute."
        case .badStatus(let code): return "Price service returned HTTP \(code)."
        case .missingAsset(let asset): return "No price returned for \(asset.ticker)."
        case .malformedResponse: return "Couldn't read the price data."
        }
    }
}

/// Minimal HTTP abstraction so the price service can be tested without the network.
public protocol HTTPClient: Sendable {
    func get(_ url: URL) async throws -> (data: Data, status: Int)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                continuation.resume(returning: (data ?? Data(), status))
            }.resume()
        }
    }
}

/// Live prices from CoinGecko's free public API (no API key required).
///
/// Endpoint: `GET /api/v3/simple/price?ids=bitcoin,ethereum,usd-coin&vs_currencies=usd&include_24hr_change=true`
public struct CoinGeckoPriceService: PriceService {
    public static let baseURL = URL(string: "https://api.coingecko.com/api/v3")!

    private let client: HTTPClient
    private let now: @Sendable () -> Date

    public init(client: HTTPClient = URLSessionHTTPClient(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.now = now
    }

    public static var requestURL: URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("simple/price"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "ids", value: Asset.allCases.map(\.coinGeckoID).joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd"),
            URLQueryItem(name: "include_24hr_change", value: "true")
        ]
        return components.url!
    }

    public func fetchPrices() async throws -> PriceSnapshot {
        let (data, status) = try await client.get(Self.requestURL)
        switch status {
        case 200: break
        case 429: throw PriceServiceError.rateLimited
        default: throw PriceServiceError.badStatus(status)
        }
        return try Self.decode(data, fetchedAt: now())
    }

    /// Parses CoinGecko's response, e.g. `{"bitcoin":{"usd":92340.12,"usd_24h_change":1.84}, ...}`.
    ///
    /// JSON numbers are read as strings first so prices become `Decimal` without a
    /// lossy trip through `Double`.
    public static func decode(_ data: Data, fetchedAt: Date) throws -> PriceSnapshot {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let root = object as? [String: Any]
        else { throw PriceServiceError.malformedResponse }

        var quotes: [Asset: PriceQuote] = [:]
        for asset in Asset.allCases {
            guard
                let entry = root[asset.coinGeckoID] as? [String: Any],
                let usd = decimal(from: entry["usd"]),
                usd > 0
            else { throw PriceServiceError.missingAsset(asset) }

            let change = decimal(from: entry["usd_24h_change"])?.rounded(2)
            quotes[asset] = PriceQuote(usd: usd.rounded(asset.isStablecoin ? 4 : 2), change24h: change)
        }
        return PriceSnapshot(quotes: quotes, fetchedAt: fetchedAt)
    }

    private static func decimal(from value: Any?) -> Decimal? {
        switch value {
        case let number as NSNumber:
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        case let double as Double:
            return Decimal(string: "\(double)", locale: Locale(identifier: "en_US_POSIX"))
        case let int as Int:
            return Decimal(int)
        case let string as String:
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        default:
            return nil
        }
    }
}
