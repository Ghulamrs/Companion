import Testing
@testable import Companion

/// Lines as the Messages API sends them, `event:` lines and blanks included.
struct StreamLineTests {
    @Test func aTextDeltaYieldsItsText() throws {
        let line = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hel"}}"#
        #expect(try ClaudeClient.text(fromStreamLine: line) == "Hel")
    }

    @Test func linesThatCarryNoTextYieldNothing() throws {
        let lines = [
            "event: content_block_delta",
            "",
            #"data: {"type":"ping"}"#,
            #"data: {"type":"message_stop"}"#,
            "data: not json",
        ]
        for line in lines {
            #expect(try ClaudeClient.text(fromStreamLine: line) == nil, "\(line)")
        }
    }

    /// Regression: an error event mid-stream was skipped like a ping, so the
    /// turn ended as if the reply were complete.
    @Test func anErrorEventThrowsWithTheAPIsMessage() throws {
        let line = #"data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#
        let error = #expect(throws: ClaudeError.self) {
            try ClaudeClient.text(fromStreamLine: line)
        }
        guard case let .stream(type, message) = error else {
            Issue.record("expected ClaudeError.stream, got \(String(describing: error))")
            return
        }
        #expect(type == "overloaded_error")
        #expect(message == "Overloaded")
    }

    /// The reader no longer insists on a space after the colon, which the
    /// event-stream format makes optional.
    @Test func theSpaceAfterDataIsOptional() throws {
        let line = #"data:{"type":"content_block_delta","delta":{"type":"text_delta","text":"x"}}"#
        #expect(try ClaudeClient.text(fromStreamLine: line) == "x")
    }
}
