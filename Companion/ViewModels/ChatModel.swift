import Foundation
import Observation

@MainActor
@Observable
final class ChatModel {
    var messages: [ChatMessage] = []
    var draft: String = ""
    var errorText: String?

    private(set) var isResponding = false

    let transport: any ChatTransport
    private var currentTurn: Task<Void, Never>?

    var systemPrompt: String? = "You are a helpful assistant inside a small iOS app. Keep replies short."

    init(transport: any ChatTransport = AppEnvironment.makeTransport()) {
        self.transport = transport
    }

    var canSend: Bool {
        !isResponding && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isResponding else { return }

        draft = ""
        errorText = nil
        messages.append(ChatMessage(role: .user, text: prompt))

        // The history sent to the model is everything *before* the placeholder.
        let history = messages
        messages.append(ChatMessage(role: .assistant, text: ""))
        isResponding = true

        currentTurn = Task { [transport, systemPrompt] in
            do {
                for try await delta in transport.stream(history: history, system: systemPrompt) {
                    guard !Task.isCancelled else { break }
                    messages[messages.count - 1].text += delta
                }
            } catch {
                // Drop the empty placeholder so the list is not left with a stub.
                if messages.last?.text.isEmpty == true {
                    messages.removeLast()
                }
                errorText = error.localizedDescription
            }

            isResponding = false
            currentTurn = nil
        }
    }

    func cancel() {
        currentTurn?.cancel()
        currentTurn = nil
        isResponding = false
        if messages.last?.text.isEmpty == true {
            messages.removeLast()
        }
    }

    func reset() {
        cancel()
        messages.removeAll()
        errorText = nil
    }
}
