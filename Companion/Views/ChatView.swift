import SwiftUI

struct ChatView: View {
    @State private var model = ChatModel()
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            transcript
                .safeAreaInset(edge: .bottom) { composer }
                .navigationTitle("Claude")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        VStack(spacing: 1) {
                            Text("Claude").font(.headline)
                            Text(model.transport.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New chat", systemImage: "square.and.pencil") {
                            model.reset()
                        }
                        .disabled(model.messages.isEmpty)
                    }
                }
                .alert(
                    "Something went wrong",
                    isPresented: Binding(
                        get: { model.errorText != nil },
                        set: { if !$0 { model.errorText = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { model.errorText = nil }
                } message: {
                    Text(model.errorText ?? "")
                }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if model.messages.isEmpty {
                        emptyState.padding(.top, 80)
                    }
                    ForEach(model.messages) { message in
                        MessageBubble(
                            message: message,
                            isStreaming: model.isResponding && message.id == model.messages.last?.id
                        )
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottomAnchor)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.messages.last?.text) {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchor, anchor: .bottom)
                }
            }
            .onChange(of: model.messages.count) {
                withAnimation { proxy.scrollTo(bottomAnchor, anchor: .bottom) }
            }
        }
    }

    private var bottomAnchor: String { "bottom" }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("Say something")
                .font(.headline)
            Text(model.transport is MockTransport
                 ? "Running offline with canned replies. Type “error” to test the failure path."
                 : "Connected to the live Messages API.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $model.draft, axis: .vertical)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.quaternary.opacity(0.5), in: .capsule)
                .focused($composerFocused)
                .onSubmit { model.send() }

            Button {
                if model.isResponding {
                    model.cancel()
                } else {
                    model.send()
                }
            } label: {
                Image(systemName: model.isResponding ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(!model.isResponding && !model.canSend)
            .animation(.default, value: model.isResponding)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

// MARK: - Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var isStreaming = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 44) }

            Group {
                if message.text.isEmpty && isStreaming {
                    TypingIndicator()
                } else {
                    Text(message.text)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                isUser ? AnyShapeStyle(Color.accentColor.opacity(0.18))
                       : AnyShapeStyle(.quaternary.opacity(0.45)),
                in: .rect(cornerRadius: 18, style: .continuous)
            )

            if !isUser { Spacer(minLength: 44) }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .frame(width: 6, height: 6)
                    .foregroundStyle(.secondary)
                    .opacity(phase == index ? 1 : 0.3)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(280))
                phase = (phase + 1) % 3
            }
        }
    }
}

#Preview("Mock conversation") {
    ChatView()
}
