import Testing
@testable import Companion

/// A transport whose streams stay open until the test closes them, so a turn
/// can be held mid-reply for as long as a test needs.
private final class HeldTransport: ChatTransport, @unchecked Sendable {
    var displayName: String { "Held · test" }

    // Only touched from the main actor in these tests.
    private(set) var continuations: [AsyncThrowingStream<String, Error>.Continuation] = []

    func stream(history: [ChatMessage], system: String?) -> AsyncThrowingStream<String, Error> {
        let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
        continuations.append(continuation)
        return stream
    }
}

@MainActor
struct ChatModelTests {
    /// Regression: the cancelled turn's task used to run its tail after the
    /// next turn had started, setting `isResponding = false` and
    /// `currentTurn = nil` on a turn that was still streaming.
    @Test func cancellingThenSendingLeavesTheNewTurnInCharge() async throws {
        let transport = HeldTransport()
        let model = ChatModel(transport: transport, configurationWarnings: [])

        model.draft = "first"
        model.send()
        let firstTurn = try #require(model.currentTurn)

        model.cancel()
        model.draft = "second"
        model.send()

        // Let the cancelled turn run to its end, whatever it does there.
        await firstTurn.value

        #expect(model.isResponding)
        #expect(model.currentTurn != nil)
        #expect(!model.canSend)
        #expect(model.errorText == nil)
        #expect(model.messages.map(\.text) == ["first", "second", ""])
        #expect(model.messages.last?.role == .assistant)

        model.cancel()
    }

    /// The happy path still clears its own state when it finishes.
    @Test func aFinishedTurnReleasesTheComposer() async throws {
        let transport = HeldTransport()
        let model = ChatModel(transport: transport, configurationWarnings: [])

        model.draft = "hello"
        model.send()
        let turn = try #require(model.currentTurn)
        // The stream is created when the turn task first runs.
        while transport.continuations.isEmpty { await Task.yield() }

        transport.continuations[0].yield("hi")
        transport.continuations[0].finish()
        await turn.value

        #expect(!model.isResponding)
        #expect(model.currentTurn == nil)
        #expect(model.messages.map(\.text) == ["hello", "hi"])
    }
}
