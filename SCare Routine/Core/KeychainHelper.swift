import Foundation
import Security

/// Hassas verileri (JWT access/refresh token) iOS Keychain'de tutan helper.
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — cihaz unlock'tan sonra
/// erişilebilir, iCloud Keychain'e sync olmaz (multi-device sync isteniyorsa değiştirilir).
enum KeychainKey: String {
    case accessToken = "scare.access_token"
    case refreshToken = "scare.refresh_token"
    case userID = "scare.user_id"
}

enum KeychainError: Error {
    case unhandledStatus(OSStatus)
    case dataInvalid
}

struct KeychainHelper {
    private static let service = "com.aliarifsoydas.scareroutine"

    static func save(_ value: String, for key: KeychainKey) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.dataInvalid
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        // Önce update dene
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if status == errSecItemNotFound {
            // Yoksa ekle
            var newItem = query
            newItem.merge(attributes) { _, new in new }
            status = SecItemAdd(newItem as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func read(_ key: KeychainKey) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    static func delete(_ key: KeychainKey) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll() {
        for key in [KeychainKey.accessToken, .refreshToken, .userID] {
            delete(key)
        }
    }
}
