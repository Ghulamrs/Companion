import Foundation

/// What this device remembers about how to reach a backend.
///
/// This exists because the scheme's environment variables only exist when Xcode
/// launches the app. Tap the icon on the home screen and they are gone — which
/// used to mean the app silently fell back to the offline mock, replying with
/// canned text while looking entirely healthy. Anything stored here survives
/// that, so the app works standing alone, off the home screen, with no Mac
/// attached and no key on the device.
///
/// The proxy address is not a secret and could have lived in UserDefaults. It
/// is here anyway: one store is simpler than two, and it inherits the same
/// this-device-only guarantee as the values that are secret.
enum DeviceConfiguration {
    /// The service name is unchanged from when this held only a key, so a key
    /// stored by an earlier build is still found rather than quietly orphaned.
    private static let apiKeyStore = KeychainStore(named: "anthropic-api-key")
    private static let proxyURLStore = KeychainStore(named: "proxy-url")
    private static let proxyTokenStore = KeychainStore(named: "proxy-token")

    static var apiKey: String? { apiKeyStore.load() }
    static var proxyToken: String? { proxyTokenStore.load() }

    /// The address as typed, so a value that fails to parse can be reported as
    /// present-but-wrong rather than silently read as absent.
    static var proxyAddress: String? { proxyURLStore.load() }
    static var proxyURL: URL? { proxyAddress.flatMap(URL.init(string:)) }

    @discardableResult static func saveAPIKey(_ value: String) -> Bool {
        apiKeyStore.save(value)
    }

    @discardableResult static func saveProxyAddress(_ value: String) -> Bool {
        proxyURLStore.save(value)
    }

    @discardableResult static func saveProxyToken(_ value: String) -> Bool {
        proxyTokenStore.save(value)
    }

    @discardableResult static func removeAPIKey() -> Bool { apiKeyStore.delete() }
    @discardableResult static func removeProxyAddress() -> Bool { proxyURLStore.delete() }
    @discardableResult static func removeProxyToken() -> Bool { proxyTokenStore.delete() }
}
