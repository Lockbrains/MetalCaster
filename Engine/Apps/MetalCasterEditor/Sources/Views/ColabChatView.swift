import SwiftUI
import MetalCasterAI

/// Chat interface for the Orchestrator (Colab tab). Shows task delegation progress.
struct ColabChatView: View {
    @Environment(EditorState.self) private var state
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            messageList

            Divider().background(MCTheme.panelBorder)

            inputBar
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if state.orchestrator.conversationHistory.isEmpty {
                        emptyState
                    } else {
                        ForEach(state.orchestrator.conversationHistory.indices, id: \.self) { i in
                            messageBubble(state.orchestrator.conversationHistory[i], index: i)
                        }
                    }
                }
                .padding(MCTheme.panelPadding)
            }
            .onChange(of: state.orchestrator.conversationHistory.count) { _, _ in
                if let last = state.orchestrator.conversationHistory.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.3")
                .font(.system(size: 24))
                .foregroundStyle(MCTheme.textTertiary)
            Text("Colab")
                .font(MCTheme.fontTitle)
                .foregroundStyle(MCTheme.textSecondary)
            Text("Describe what you want to build.\nThe Orchestrator will plan and\ncoordinate agents to build it.")
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func messageBubble(_ message: ChatMessage, index: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(message.role == .user ? MCTheme.statusBlue : orchestratorColor)
                .frame(width: 5, height: 5)
                .padding(.top, 5)

            Text(message.content)
                .font(MCTheme.fontBody)
                .foregroundStyle(
                    message.role == .user ? MCTheme.textPrimary : MCTheme.textSecondary
                )
                .textSelection(.enabled)
        }
        .id(index)
    }

    private var orchestratorColor: Color {
        switch state.orchestrator.status {
        case .idle:      return MCTheme.statusGray
        case .thinking:  return MCTheme.statusBlue
        case .executing: return MCTheme.statusGreen
        case .error:     return MCTheme.statusRed
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Describe what you want to build...", text: $inputText)
                .textFieldStyle(.plain)
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)
                .onSubmit { sendMessage() }

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            inputText.isEmpty ? MCTheme.textTertiary : MCTheme.textPrimary
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
        }
        .padding(.horizontal, MCTheme.panelPadding)
        .padding(.vertical, 8)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isLoading = true

        Task {
            do {
                let snapshot = state.engineAPI.takeSnapshot()
                let _ = try await state.orchestrator.chat(
                    message: text,
                    snapshot: snapshot,
                    settings: state.aiSettings
                )
                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    state.orchestrator.conversationHistory.append(
                        ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
                    )
                    isLoading = false
                }
            }
        }
    }
}
