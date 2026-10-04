import Foundation

// MARK: - Wire types

private struct WireMessage: Encodable {
    let role: String
    let content: String
}

private struct MessagesRequest: Encodable {
    let model: String
    let max_tokens: Int
    let system: String?
    let messages: [WireMessage]
    let stream: Bool
}

private struct StreamEvent: Decodable {
    struct Delta: Decodable {
        let type: String?
        let text: String?
    }
    let type: String
    let delta: Delta?
    /// Present on an `error` event.
    let error: APIErrorEnvelope.Payload?
}

private struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        let type: String
        let message: String
    }
    let error: Payload
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case http(status: Int, message: String)
    /// An `error` event inside a stream that had already answered 200.
    case stream(type: String, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case let .http(status, message):
            "Claude API error \(status): \(message)"
        case let .stream(type, message):
            "Claude stopped mid-reply (\(type)): \(message)"
        case .badResponse:
            "Unexpected response from the Claude API."
        }
    }
}

// MARK: - Client

/// Talks to the Messages API over plain URLSession. Works on iOS 26 with no
/// third-party dependencies.
struct ClaudeClient: ChatTransport {
    let baseURL: URL
    let model: String
    let maxTokens: Int

    /// Headers that authenticate the caller.
    /// Development: `["x-api-key": key]` straight to api.anthropic.com.
    /// Production: your own header, with `baseURL` pointing at your proxy.
    private let authHeaders: [String: String]
    private let isDirect: Bool

    init(
        baseURL: URL = URL(string: "https://api.anthropic.com")!,
        authHeaders: [String: String],
        model: String = "claude-sonnet-5",
        maxTokens: Int = 1024,
        isDirect: Bool = true
    ) {
        self.baseURL = baseURL
        self.authHeaders = authHeaders
        self.model = model
        self.maxTokens = maxTokens
        self.isDirect = isDirect
    }

    var displayName: String {
        isDirect ? "Claude · \(model)" : "Claude · via proxy"
    }

    // MARK: Request construction

    private func makeRequest(_ body: MessagesRequest) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        for (field, value) in authHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    private func body(history: [ChatMessage], system: String?) -> MessagesRequest {
        MessagesRequest(
            model: model,
            max_tokens: maxTokens,
            system: system,
            // The Messages API is stateless: send the whole history every turn.
            messages: history.map { WireMessage(role: $0.role.rawValue, content: $0.text) },
            stream: true
        )
    }

    private func errorMessage(from data: Data) -> String {
        (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
            ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Streaming

    /// Reduces one line of the event stream to the text it adds, if any.
    ///
    /// Throws for an `error` event. The API sends one mid-stream, after the 200
    /// and possibly after some text, when it cannot finish a reply — an
    /// `overloaded_error` is the usual case. Dropping it, as this once did,
    /// ended the turn as if it had finished: a reply cut short with no word of
    /// why, or an empty bubble.
    static func text(fromStreamLine line: String) throws -> String? {
        guard line.hasPrefix("data:") else { return nil }
        var payload = line.dropFirst(5)
        if payload.first == " " { payload = payload.dropFirst() }

        guard let event = try? JSONDecoder().decode(StreamEvent.self, from: Data(payload.utf8))
        else { return nil }

        switch event.type {
        case "content_block_delta":
            return event.delta?.text
        case "error":
            throw ClaudeError.stream(
                type: event.error?.type ?? "error",
                message: event.error?.message ?? "The stream reported an error without a message."
            )
        default:
            return nil
        }
    }

    func stream(
        history: [ChatMessage],
        system: String?
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(body(history: history, system: system))
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw ClaudeError.badResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        // A non-2xx answer is a JSON error envelope, not an event stream;
                        // drain it for the message.
                        var raw = Data()
                        for try await byte in bytes { raw.append(byte) }
                        throw ClaudeError.http(
                            status: http.statusCode,
                            message: errorMessage(from: raw)
                        )
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        if let text = try Self.text(fromStreamLine: line) {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
