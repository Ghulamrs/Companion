import Foundation

/// Streams canned replies with realistic pacing. No network, no key, no cost.
/// This is what the app uses by default, so a fresh clone runs immediately.
///
/// Type `error` in the chat to exercise the failure path.
struct MockTransport: ChatTransport {
    var displayName: String { "Mock · offline" }

    /// Pause between emitted chunks. Lower it if the typing feels slow.
    var chunkDelay: Duration = .milliseconds(45)

    /// Pause before the first chunk, imitating time-to-first-token.
    var leadIn: Duration = .milliseconds(350)

    enum MockError: LocalizedError {
        case simulated

        var errorDescription: String? {
            "Simulated transport failure. This is the mock backend proving the error path works."
        }
    }

    func stream(
        history: [ChatMessage],
        system: String?
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = history.last?.text.lowercased() ?? ""
        let shouldFail = prompt.contains("error") || prompt.contains("fail")
        let reply = Self.reply(for: prompt, turnCount: history.count)

        return AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: leadIn)

                if shouldFail {
                    continuation.finish(throwing: MockError.simulated)
                    return
                }

                // Emit word by word so the UI exercises the same incremental
                // append path it will use against the real streaming API.
                for chunk in Self.chunks(of: reply) {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(chunk)
                    try? await Task.sleep(for: chunkDelay)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Canned content

    private static func chunks(of text: String) -> [String] {
        text.split(separator: " ", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : " " + String($0.element) }
    }

    private static func reply(for prompt: String, turnCount: Int) -> String {
        if prompt.contains("hello") || prompt.contains("hi ") || prompt == "hi" {
            return """
            Hey. You are talking to the mock transport, which means the app is \
            wired up correctly and no API key is involved yet. Ask me anything \
            and I will keep improvising placeholder text.
            """
        }

        if prompt.contains("swift") || prompt.contains("swiftui") {
            return """
            SwiftUI's job here is small on purpose: the view owns no networking \
            logic at all. It observes ChatModel, which holds an `any ChatTransport`. \
            Swapping the mock for the live client is a one-line change in \
            AppEnvironment.makeTransport().
            """
        }

        if prompt.contains("key") || prompt.contains("api") {
            return """
            To go live, set ANTHROPIC_API_KEY in the scheme's environment \
            variables and relaunch. The app detects it at startup and routes \
            through ClaudeClient instead of me. Nothing else changes.
            """
        }

        if prompt.contains("stream") {
            return """
            Streaming works the same in both transports: an AsyncThrowingStream \
            of String deltas that the view model appends onto the last message. \
            The real client parses server-sent events; I just split a string on \
            spaces and sleep between them.
            """
        }

        return """
        Turn \(turnCount / 2 + 1) of this mock conversation. I do not understand \
        your message — I am a lookup table with a sleep timer. What I do prove is \
        that the message list, the streaming append, the scroll-to-bottom, the \
        cancel button, and the error alert all behave before you spend a single \
        token on the real API.
        """
    }
}
