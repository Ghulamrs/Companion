import Foundation
import Security

/// One value at rest in the Keychain.
///
/// Why here rather than in source, an xcconfig, or an Info.plist: all three end
/// up inside the built binary, and a secret inside a binary is extractable by
/// anyone holding the app. A value in the Keychain is typed once on the device
/// that uses it. It never enters the build, and never enters the repository —
/// which matters more than usual here, because this repository is public.
struct KeychainStore {
    /// Scoped to the bundle identifier, so a build with a different identity
    /// does not silently inherit a value stored for another one.
    private let service: String
    private let account = "default"

    init(named name: String) {
        service = (Bundle.main.bundleIdentifier ?? "Companion") + "." + name
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> String? {
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
    func save(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
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
    func delete() -> Bool {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Enough of a secret to recognise which one is stored, and no more. Never
    /// show or log the whole value — a credential on screen is one in a
    /// screenshot.
    static func redacted(_ value: String) -> String {
        guard value.count > 12 else { return "••••" }
        return value.prefix(8) + "…" + value.suffix(4)
    }
}
