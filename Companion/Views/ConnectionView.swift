import SwiftUI

/// Where the app is told how to reach a backend, on the device that will use it.
///
/// Deliberately the only place in the app that accepts a credential, and it
/// never displays one it already holds — stored secrets are shown redacted, so
/// a screenshot of this screen is not a leak.
///
/// The proxy fields are the point of it. Without them the proxy could only be
/// configured through the Xcode scheme, which meant it worked only while
/// tethered to a Mac: launched from the home screen the app found no
/// configuration and fell back to the offline mock, answering convincingly
/// while sending nothing anywhere.
struct ConnectionView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called after stored configuration changes, so the model can rebuild its
    /// backend without a relaunch.
    let onChange: () -> Void

    @State private var proxyAddressEntry: String = ""
    @State private var proxyTokenEntry: String = ""
    @State private var keyEntry: String = ""

    @State private var storedProxyAddress: String?
    @State private var storedProxyToken: String?
    @State private var storedKey: String?

    @State private var failed = false

    private var trimmedAddress: String {
        proxyAddressEntry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The client appends `v1/messages` itself, so an address that already ends
    /// in it produces a doubled path and a 404 that looks like a server fault.
    private var addressLooksDoubled: Bool {
        trimmedAddress.hasSuffix("/v1/messages") || trimmedAddress.hasSuffix("/v1/messages/")
    }

    private var keyLooksWrong: Bool {
        let trimmed = keyEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.hasPrefix("sk-ant-")
    }

    private var hasSomethingToSave: Bool {
        !trimmedAddress.isEmpty
            || !proxyTokenEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !keyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                if AppEnvironment.schemeProxyURL != nil || AppEnvironment.apiKey != nil {
                    Section {
                        Label(
                            "The Xcode scheme is setting configuration, and the environment wins. What you save here applies when the app runs without it — launched from the home screen, for instance.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                    }
                }

                Section {
                    TextField("https://example.com/ai", text: $proxyAddressEntry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(.body.monospaced())

                    SecureField("proxy token", text: $proxyTokenEntry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    if addressLooksDoubled {
                        Label(
                            "Leave off /v1/messages — the app adds that itself.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Proxy")
                } footer: {
                    Text("The address of your relay, and the token it issued you. The Anthropic key stays on that server and never reaches this phone — so if the token leaks it costs a revocation, not a bill. This is the arrangement that is safe to ship.")
                }

                Section {
                    SecureField("sk-ant-…", text: $keyEntry)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    if keyLooksWrong {
                        Label(
                            "That does not start with sk-ant-. You can still save it, but check it is the key's value and not its name.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                } header: {
                    Text("API key")
                } footer: {
                    Text("A development shortcut, used only when no proxy is set. The key sits on this phone and is spent directly, so it is not what you hand to anyone else.")
                }

                if storedProxyAddress != nil || storedProxyToken != nil || storedKey != nil {
                    Section("Saved on this device") {
                        if let storedProxyAddress {
                            LabeledContent("Proxy", value: storedProxyAddress)
                                .font(.body.monospaced())
                            Button("Remove proxy address", role: .destructive) {
                                DeviceConfiguration.removeProxyAddress()
                                changed()
                            }
                        }
                        if let storedProxyToken {
                            LabeledContent("Token", value: storedProxyToken)
                                .font(.body.monospaced())
                            Button("Remove token", role: .destructive) {
                                DeviceConfiguration.removeProxyToken()
                                changed()
                            }
                        }
                        if let storedKey {
                            LabeledContent("API key", value: storedKey)
                                .font(.body.monospaced())
                            Button("Remove key", role: .destructive) {
                                DeviceConfiguration.removeAPIKey()
                                changed()
                            }
                        }
                    }
                }

                if failed {
                    Section {
                        Label("The Keychain refused to store that.", systemImage: "xmark.octagon")
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!hasSomethingToSave)
                }
            }
            .onAppear(perform: refresh)
        }
    }

    /// Saves whatever was filled in, and leaves the rest alone. Clearing a value
    /// is done with its Remove button, so an empty field can never wipe
    /// something by accident.
    private func save() {
        var ok = true

        if !trimmedAddress.isEmpty {
            ok = DeviceConfiguration.saveProxyAddress(trimmedAddress) && ok
        }
        if !proxyTokenEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ok = DeviceConfiguration.saveProxyToken(proxyTokenEntry) && ok
        }
        if !keyEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ok = DeviceConfiguration.saveAPIKey(keyEntry) && ok
        }

        failed = !ok
        guard ok else { return }

        // Do not keep plaintext around in view state once it is stored.
        proxyAddressEntry = ""
        proxyTokenEntry = ""
        keyEntry = ""

        changed()
        dismiss()
    }

    private func changed() {
        refresh()
        onChange()
    }

    private func refresh() {
        storedProxyAddress = DeviceConfiguration.proxyAddress
        storedProxyToken = DeviceConfiguration.proxyToken.map(KeychainStore.redacted)
        storedKey = DeviceConfiguration.apiKey.map(KeychainStore.redacted)
    }
}
