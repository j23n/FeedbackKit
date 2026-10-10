#if canImport(Security)
import Foundation
import Security

/// Keeps the token in the Keychain, synchronized through iCloud Keychain when it's on, so it's
/// entered once per app rather than once per device.
public struct KeychainTokenStore: TokenStore {
    public struct Failure: Error, LocalizedError {
        public let status: OSStatus
        public var errorDescription: String? { "The Keychain refused the token (\(status))." }
    }

    public let service: String
    public let account: String

    public init(service: String = "FeedbackKit", account: String) {
        self.service = service
        self.account = account
    }

    public func token() -> String? {
        var query = baseQuery
        query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func setToken(_ token: String?) throws {
        var existing = baseQuery
        existing[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        SecItemDelete(existing as CFDictionary)
        guard let token, !token.isEmpty else { return }

        var item = baseQuery
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrSynchronizable as String] = true
        var status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            // Without iCloud Keychain (or its entitlement), keep it on this device only.
            item[kSecAttrSynchronizable as String] = false
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Failure(status: status) }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}
#endif
