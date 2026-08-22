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
enum AppEnvironment {
    private static func value(_ name: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static var apiKey: String? { value("ANTHROPIC_API_KEY") }
    static var proxyURL: URL? { value("CLAUDE_PROXY_URL").flatMap(URL.init(string:)) }
    static var proxyToken: String? { value("CLAUDE_PROXY_TOKEN") }
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

        if value("CLAUDE_PROXY_URL") != nil, proxyURL == nil {
            warnings.append(
                "CLAUDE_PROXY_URL is set but is not a valid URL, so it was ignored."
            )
        }

        if proxyURL == nil, proxyToken != nil {
            warnings.append(
                "CLAUDE_PROXY_TOKEN is set but CLAUDE_PROXY_URL is not. The token is going nowhere."
            )
        }

        if proxyToken == nil, value("CLAUDE_PROXY_AUTH_HEADER") != nil {
            warnings.append(
                "CLAUDE_PROXY_AUTH_HEADER is set but CLAUDE_PROXY_TOKEN is not, so no auth header is sent."
            )
        }

        if proxyURL != nil, apiKey != nil {
            warnings.append(
                "ANTHROPIC_API_KEY is set, but the proxy wins. The key is never read and never forwarded."
            )
        }

        if let proxyURL, proxyURL.scheme?.lowercased() != "https", !isLoopback(proxyURL) {
            warnings.append(
                "CLAUDE_PROXY_URL is not https. App Transport Security will block the request."
            )
        }

        // Catches the classic slip of pasting the key over the variable *name*.
        if let apiKey, !apiKey.hasPrefix("sk-ant-") {
            warnings.append(
                "ANTHROPIC_API_KEY does not look like a key. Set the key as the variable's value, not as its name."
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

        if let apiKey {
            return ClaudeClient(
                authHeaders: ["x-api-key": apiKey],
                model: model
            )
        }

        return MockTransport()
    }
}
