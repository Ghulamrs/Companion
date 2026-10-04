import Testing
@testable import Companion

/// The mock is how the UI gets iterated without spending tokens (HANDOFF,
/// invariant 4). These pin the two behaviours the manual table relies on, so
/// they cannot rot silently as the real client evolves.
struct MockTransportTests {
    private let mock = MockTransport(chunkDelay: .zero, leadIn: .zero)

    @Test func streamsAReplyInMoreThanOneChunk() async throws {
        var chunks: [String] = []
        for try await chunk in mock.stream(history: [ChatMessage(role: .user, text: "hello")], system: nil) {
            chunks.append(chunk)
        }
        #expect(chunks.count > 1)
        #expect(chunks.joined().contains("mock transport"))
    }

    @Test func failsWhenAskedTo() async {
        await #expect(throws: MockTransport.MockError.self) {
            for try await _ in mock.stream(history: [ChatMessage(role: .user, text: "error")], system: nil) {}
        }
    }
}
