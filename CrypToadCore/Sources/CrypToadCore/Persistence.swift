import Foundation

/// Loads and saves the user's `PortfolioState`.
public protocol PortfolioRepository: Sendable {
    /// Returns the saved state, or `nil` if nothing has been saved yet.
    func load() throws -> PortfolioState?
    func save(_ state: PortfolioState) throws
    func reset() throws
}

/// Stores state as a JSON file (in Application Support on iOS).
///
/// JSON keeps the storage format readable, versionable, and fully testable on any
/// platform. Writes are atomic, so a crash mid-save can't corrupt the file.
public struct FileRepository: PortfolioRepository {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/CrypToad/portfolio.json`
    public static func defaultURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("CrypToad", isDirectory: true)
            .appendingPathComponent("portfolio.json")
    }

    public func load() throws -> PortfolioState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(PortfolioState.self, from: data)
    }

    public func save(_ state: PortfolioState) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try Self.encoder.encode(state)
        try data.write(to: url, options: .atomic)
    }

    public func reset() throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Keeps state in memory only. Used for previews and tests.
public final class InMemoryRepository: PortfolioRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PortfolioState?

    public init(_ initial: PortfolioState? = nil) {
        stored = initial
    }

    public func load() throws -> PortfolioState? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ state: PortfolioState) throws {
        lock.lock(); defer { lock.unlock() }
        stored = state
    }

    public func reset() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
