import Foundation
import Security

/// The API key at rest, in the Keychain.
///
/// Why here rather than in source, an xcconfig, or an Info.plist: all three of
/// those end up inside the built binary, and a key inside a binary is
/// extractable by anyone holding the app. A key in the Keychain is typed once
/// on the device that uses it. It never enters the build, and never enters the
/// repository — which matters more than usual here, because this repository is
/// public.
///
/// This is still a development convenience, not a shipping design. For anything
/// you hand to another person, stand up the proxy and leave the key server-side.
enum APIKeyStore {
    /// Scoped to the bundle identifier, so a build with a different identity
    /// does not silently inherit a key that was stored for another one.
    private static var service: String {
        (Bundle.main.bundleIdentifier ?? "Companion") + ".anthropic-api-key"
    }

    private static let account = "default"

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let text = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete() }

        // Delete-then-add rather than update: one code path, no stale attributes.
        delete()

        var query = baseQuery()
        query[kSecValueData as String] = Data(trimmed.utf8)
        // Stays on this device. Not synced to iCloud Keychain, and not carried
        // onto a different phone by an encrypted backup.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Enough of the key to recognise which one is stored, and no more. Never
    /// show or log the whole value — a key on screen is a key in a screenshot.
    static func redacted(_ key: String) -> String {
        guard key.count > 12 else { return "••••" }
        return key.prefix(8) + "…" + key.suffix(4)
    }
}
