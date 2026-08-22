import Foundation
import Observation

@MainActor
@Observable
final class ChatModel {
    var messages: [ChatMessage] = []
    var draft: String = ""
    var errorText: String?

    private(set) var isResponding = false

    /// Not `let`: storing a key on the device changes which backend the app
    /// should be talking to, and that has to take effect without a relaunch.
    private(set) var transport: any ChatTransport

    /// Misconfiguration worth showing rather than swallowing. See
    /// `AppEnvironment.configurationWarnings`.
    private(set) var configurationWarnings: [String]

    private var currentTurn: Task<Void, Never>?

    var systemPrompt: String? = "You are a helpful assistant inside a small iOS app. Keep replies short."

    init(
        transport: any ChatTransport = AppEnvironment.makeTransport(),
        configurationWarnings: [String] = AppEnvironment.configurationWarnings
    ) {
        self.transport = transport
        self.configurationWarnings = configurationWarnings
    }

    /// Rebuild the backend from current configuration. Called after the stored
    /// key changes. Any turn in flight belongs to the old backend, so it is
    /// cancelled rather than left to finish against a client being replaced.
    func reloadTransport() {
        cancel()
        transport = AppEnvironment.makeTransport()
        configurationWarnings = AppEnvironment.configurationWarnings
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
