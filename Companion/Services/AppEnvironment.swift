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
///   ANTHROPIC_API_KEY   sk-ant-...                 (development only)
///   CLAUDE_PROXY_URL    https://api.yourapp.com    (preferred for real builds)
///   CLAUDE_MODEL        claude-sonnet-5            (optional override)
enum AppEnvironment {
    private static func value(_ name: String) -> String? {
        let raw = ProcessInfo.processInfo.environment[name]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw, !raw.isEmpty else { return nil }
        return raw
    }

    static var apiKey: String? { value("ANTHROPIC_API_KEY") }
    static var proxyURL: URL? { value("CLAUDE_PROXY_URL").flatMap(URL.init(string:)) }
    static var model: String { value("CLAUDE_MODEL") ?? "claude-sonnet-5" }

    static func makeTransport() -> any ChatTransport {
        // A proxy wins if configured: it is the only arrangement that is safe to ship.
        if let proxyURL {
            return ClaudeClient(
                baseURL: proxyURL,
                authHeaders: [:],
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
