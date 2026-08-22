import Foundation

/// Decides which backend the app talks to, based on environment variables set
/// in the Xcode scheme. With nothing set, you get the offline mock.
///
/// Environment variables live in the scheme, not in the binary, so no key is
/// ever compiled into the app. That matters: a key bundled into a shipping
/// build is extractable, and whoever extracts it bills your account.
///
///   Product ▸ Scheme ▸ Edit Scheme… ▸ Run ▸ Arguments ▸ Environment Variables
///
///   ANTHROPIC_API_KEY                         (development only)
///   CLAUDE_PROXY_URL          https://api.yourapp.com   (preferred for real builds)
///   CLAUDE_PROXY_TOKEN        whatever your proxy issues this install
///   CLAUDE_PROXY_AUTH_HEADER  header name for the token (default Authorization)
///   CLAUDE_MODEL              claude-sonnet-5           (optional override)
///
/// Anything saved on the device (see `DeviceConfiguration`) acts as a fallback
/// beneath these. The environment always wins, so setting a variable in the
/// scheme overrides what is on the device without having to clear it first.
///
/// The device layer is what makes the app usable off the home screen. Launched
/// by tapping its icon, a build has none of these variables — and before the
/// proxy could be stored, that meant silently falling back to the offline mock,
/// which answers convincingly and sends nothing anywhere.
enum AppEnvironment {
    private static func value(_ name: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    /// The key from the scheme's environment. Present only for launches Xcode
    /// performs — tapping the app's icon on a device gets you none of these.
    static var apiKey: String? { value("ANTHROPIC_API_KEY") }

    /// The key typed into the app on this device, if any.
    static var storedAPIKey: String? { DeviceConfiguration.apiKey }

    /// What the app will actually authenticate with. Environment first, so a
    /// scheme variable overrides the device without clearing it.
    static var effectiveAPIKey: String? { apiKey ?? storedAPIKey }
    /// The proxy from the scheme, kept separate so a bad value there can be
    /// reported against the variable that carries it.
    static var schemeProxyURL: URL? { value("CLAUDE_PROXY_URL").flatMap(URL.init(string:)) }

    /// What the app will actually call. Environment first, device second.
    static var proxyURL: URL? { schemeProxyURL ?? DeviceConfiguration.proxyURL }
    static var proxyToken: String? { value("CLAUDE_PROXY_TOKEN") ?? DeviceConfiguration.proxyToken }
    static var model: String { value("CLAUDE_MODEL") ?? "claude-sonnet-5" }

    /// Header the proxy token is sent under. Bearer auth is the common case, so
    /// it is the default; override it for gateways that want their own name,
    /// such as Cloudflare Access and its `CF-Access-Client-Secret`.
    static var proxyAuthHeaderName: String {
        value("CLAUDE_PROXY_AUTH_HEADER") ?? "Authorization"
    }

    /// How this app proves to *your* proxy that it is allowed to call it.
    ///
    /// This is a separate concern from the Anthropic key: the proxy holds that
    /// server-side and the app never sees it. What the app sends is only ever a
    /// token scoped to the proxy, so a leaked one costs you a revocation rather
    /// than an unbounded bill.
    ///
    /// Empty when no token is set. That is deliberate — a proxy may authorize
    /// callers by other means (mutual TLS, an identity-aware gateway, a network
    /// boundary), and refusing to start in those setups would be wrong.
    ///
    /// The token travels over TLS: App Transport Security blocks cleartext HTTP
    /// by default, so an `http://` proxy URL fails the request rather than
    /// sending the token in the clear.
    static var proxyAuthHeaders: [String: String] {
        guard let proxyToken else { return [:] }

        let name = proxyAuthHeaderName
        let usesBearer = name.caseInsensitiveCompare("Authorization") == .orderedSame
        return [name: usesBearer ? "Bearer \(proxyToken)" : proxyToken]
    }

    /// Configuration that will be silently ignored, or that contradicts itself.
    ///
    /// Only `CLAUDE_PROXY_URL` and `ANTHROPIC_API_KEY` actually select a backend.
    /// The rest are modifiers, and a modifier without the thing it modifies does
    /// nothing at all — which is the kind of mistake that costs an hour, because
    /// the app comes up looking fine and simply talks to the wrong backend.
    ///
    /// Never include a credential's value in a warning. Naming the variable is
    /// enough to fix it, and a warning that quotes a key just moves the key
    /// somewhere new.
    static var configurationWarnings: [String] {
        var warnings: [String] = []

        if value("CLAUDE_PROXY_URL") != nil, schemeProxyURL == nil {
            warnings.append(
                "CLAUDE_PROXY_URL is set in the scheme but is not a valid URL, so it was ignored."
            )
        }

        if DeviceConfiguration.proxyAddress != nil, DeviceConfiguration.proxyURL == nil {
            warnings.append(
                "The proxy address saved on this device is not a valid URL, so it was ignored."
            )
        }

        if proxyURL == nil, proxyToken != nil {
            warnings.append(
                "A proxy token is set but no proxy address is. The token is going nowhere."
            )
        }

        if proxyToken == nil, value("CLAUDE_PROXY_AUTH_HEADER") != nil {
            warnings.append(
                "CLAUDE_PROXY_AUTH_HEADER is set but no proxy token is, so no auth header is sent."
            )
        }

        // Not every proxy wants a token — some authorise by mutual TLS or by
        // network boundary — so this reports the likely outcome rather than
        // calling it an error.
        if proxyURL != nil, proxyToken == nil {
            warnings.append(
                "No proxy token is set. A proxy that authorises its callers will answer 401."
            )
        }

        // Names neither variable: the key in play may have come from the scheme
        // or from this device, and naming the wrong one sends you hunting in
        // the wrong place.
        if proxyURL != nil, effectiveAPIKey != nil {
            warnings.append(
                "An API key is set, but the proxy wins. The key is never read and never forwarded."
            )
        }

        if let proxyURL, proxyURL.scheme?.lowercased() != "https", !isLoopback(proxyURL) {
            warnings.append(
                "The proxy address is not https. App Transport Security will block the request."
            )
        }

        // Catches the classic slip of pasting the key over the variable *name*.
        if let effectiveAPIKey, !effectiveAPIKey.hasPrefix("sk-ant-") {
            warnings.append(
                "The API key in use does not look like a key (expected it to start with sk-ant-)."
            )
        }

        return warnings
    }

    private static func isLoopback(_ url: URL) -> Bool {
        switch url.host()?.lowercased() {
        case "localhost", "127.0.0.1", "::1": true
        default: false
        }
    }

    static func makeTransport() -> any ChatTransport {
        // A proxy wins if configured: it is the only arrangement that is safe to ship.
        if let proxyURL {
            return ClaudeClient(
                baseURL: proxyURL,
                authHeaders: proxyAuthHeaders,
                model: model,
                isDirect: false
            )
        }

        if let effectiveAPIKey {
            return ClaudeClient(
                authHeaders: ["x-api-key": effectiveAPIKey],
                model: model
            )
        }

        return MockTransport()
    }
}
