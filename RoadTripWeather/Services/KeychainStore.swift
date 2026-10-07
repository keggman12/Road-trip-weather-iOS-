import Foundation
import Security

/// Minimal Keychain wrapper for the optional Open Charge Map key. Nothing
/// else in the app is secret.
struct KeychainStore: Sendable {
    let service: String

    init(service: String = "com.keggman12.RoadTripWeather") {
        self.service = service
    }

    func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    func write(_ value: String, account: String) -> Bool {
        delete(account)
        guard let data = value.data(using: .utf8) else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static let openChargeMapAccount = "openchargemap-api-key"
}

/// Phase 2: Tesla Supercharger lookup. Disabled until the user stores a key.
struct OpenChargeMapService: ChargerService {
    let keychain: KeychainStore

    var isConfigured: Bool {
        !(keychain.read(KeychainStore.openChargeMapAccount) ?? "").isEmpty
    }
}
