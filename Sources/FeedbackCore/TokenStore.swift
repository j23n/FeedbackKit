import Foundation

/// Keeps the GitHub token: the Keychain in the apps (FeedbackKit's `KeychainTokenStore`),
/// memory in tests and previews.
public protocol TokenStore: Sendable {
    func token() -> String?
    /// Saves a token, or removes it when `nil`.
    func setToken(_ token: String?) throws
}

/// A token kept in memory, for tests and previews.
public final class MemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(token: String? = nil) {
        value = token
    }

    public func token() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func setToken(_ token: String?) throws {
        lock.lock()
        defer { lock.unlock() }
        value = token
    }
}
