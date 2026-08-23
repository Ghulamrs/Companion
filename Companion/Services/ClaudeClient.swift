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
    case badResponse

    var errorDescription: String? {
        switch self {
        case let .http(status, message):
            "Claude API error \(status): \(message)"
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
                        // The body is an SSE stream even on failure; drain it for the message.
                        var raw = Data()
                        for try await byte in bytes { raw.append(byte) }
                        throw ClaudeError.http(
                            status: http.statusCode,
                            message: errorMessage(from: raw)
                        )
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = Data(line.dropFirst(6).utf8)
                        guard let event = try? decoder.decode(StreamEvent.self, from: payload)
                        else { continue }

                        if event.type == "content_block_delta", let text = event.delta?.text {
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
