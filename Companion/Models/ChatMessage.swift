import Foundation

/// One turn in the conversation. Kept deliberately separate from the API wire
/// types so the UI never has to care how the request is serialized.
struct ChatMessage: Identifiable, Hashable, Sendable {
    enum Role: String, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}
