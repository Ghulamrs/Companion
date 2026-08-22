import SwiftUI

/// Where the key gets typed on the device that uses it.
///
/// Deliberately the only place in the app that accepts a credential, and it
/// never displays one it already holds — a stored key is shown redacted, so a
/// screenshot of this screen is not a leak.
struct APIKeyView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called after the stored key changes, so the model can rebuild its backend.
    let onChange: () -> Void

    @State private var entry: String = ""
    @State private var storedRedacted: String?
    @State private var failed = false

    private var entryLooksWrong: Bool {
        let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("sk-ant-")
    }

    var body: some View {
        NavigationStack {
            Form {
                if AppEnvironment.apiKey != nil {
                    Section {
                        Label(
                            "ANTHROPIC_API_KEY is set in the scheme, and the environment wins. A key stored here will be ignored until you clear it.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                    }
                }

                Section {
                    SecureField("sk-ant-…", text: $entry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    if entryLooksWrong {
                        Label(
                            "That does not start with sk-ant-. You can still save it, but check it is the key's value and not its name.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Key")
                } footer: {
                    Text("Stored in the Keychain on this device only. It is never written into the app, the project, or the repository, and it is not synced to iCloud or carried onto another phone by a backup.")
                }

                if let storedRedacted {
                    Section("Stored") {
                        LabeledContent("On this device", value: storedRedacted)
                            .font(.body.monospaced())
                        Button("Remove key", role: .destructive) {
                            APIKeyStore.delete()
                            refresh()
                            onChange()
                        }
                    }
                }

                if failed {
                    Section {
                        Label("The Keychain refused to store the key.", systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("API key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(entry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: refresh)
        }
    }

    private func save() {
        let ok = APIKeyStore.save(entry)
        failed = !ok
        guard ok else { return }
        // Do not keep the plaintext around in view state once it is stored.
        entry = ""
        refresh()
        onChange()
        dismiss()
    }

    private func refresh() {
        storedRedacted = APIKeyStore.load().map(APIKeyStore.redacted)
    }
}
