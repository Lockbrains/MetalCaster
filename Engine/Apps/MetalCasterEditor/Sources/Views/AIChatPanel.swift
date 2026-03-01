import SwiftUI
import MetalCasterCore
import MetalCasterAI
import MetalCasterScene

struct AIChatPanel: View {
    @Environment(EditorState.self) private var state
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider().background(MCTheme.panelBorder)

            messageList

            Divider().background(MCTheme.panelBorder)

            inputBar
        }
        .background(MCTheme.background)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack {
            Text("AI")
                .font(MCTheme.fontPanelLabel)
                .foregroundStyle(MCTheme.textSecondary)
            Text("Chat")
                .font(MCTheme.fontPanelLabelBold)
                .foregroundStyle(MCTheme.textPrimary)
            Spacer()
            Button {
                state.showAIChat = false
            } label: {
                Image(systemName: "xmark")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(state.chatMessages.indices, id: \.self) { i in
                    messageBubble(state.chatMessages[i])
                }
            }
            .padding(16)
        }
    }

    private func messageBubble(_ message: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(message.role == .user ? MCTheme.statusBlue : MCTheme.statusGray)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            Text(message.content)
                .font(MCTheme.fontBody)
                .foregroundStyle(
                    message.role == .user
                        ? MCTheme.textPrimary
                        : MCTheme.textSecondary
                )
                .textSelection(.enabled)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask about your scene...", text: $inputText)
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
                        .font(.system(size: 18))
                        .foregroundStyle(
                            inputText.isEmpty
                                ? MCTheme.textTertiary
                                : MCTheme.textPrimary
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        state.chatMessages.append(ChatMessage(role: .user, content: text))
        isLoading = true

        let sceneContext = "Scene: \(state.sceneName), \(state.engine.world.entityCount) entities"

        Task {
            let service = AIService.shared
            do {
                let response = try await service.agentChat(
                    messages: state.chatMessages,
                    context: sceneContext,
                    dataFlowDescription: "",
                    settings: state.aiSettings
                )
                await MainActor.run {
                    state.chatMessages.append(
                        ChatMessage(role: .assistant, content: response.explanation)
                    )
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    state.chatMessages.append(
                        ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
                    )
                    isLoading = false
                }
            }
        }
    }
}
