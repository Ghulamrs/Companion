import Foundation

/// Everything the UI needs from a backend. `MockTransport` and `ClaudeClient`
/// both satisfy it, so you can run the whole app with no API key and swap in
/// the real thing later without touching a single view.
protocol ChatTransport: Sendable {
    /// Shown in the nav bar so you always know which backend you are talking to.
    var displayName: String { get }

    /// Yields incremental text deltas. Finishing the stream ends the turn.
    func stream(
        history: [ChatMessage],
        system: String?
    ) -> AsyncThrowingStream<String, Error>
}
