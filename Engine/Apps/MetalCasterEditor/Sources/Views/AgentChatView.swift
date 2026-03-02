import SwiftUI
import MetalCasterAI

/// Chat interface for a single specialist agent.
struct AgentChatView: View {
    @Environment(EditorState.self) private var state
    let agent: MCAgent
    let onBack: () -> Void

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
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                onBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
            }
            .buttonStyle(.plain)

            MCStatusDot(color: statusColor)

            Image(systemName: agent.role.icon)
                .font(MCTheme.fontCaption)
                .foregroundStyle(MCTheme.textSecondary)

            Text(agent.role.displayName)
                .font(MCTheme.fontBody)
                .foregroundStyle(MCTheme.textPrimary)

            Spacer()

            if agent.status == .thinking || agent.status == .executing {
                ProgressView()
                    .controlSize(.small)
            }

            Text(agent.status.rawValue)
                .font(MCTheme.fontSmall)
                .foregroundStyle(MCTheme.textTertiary)
        }
        .padding(.horizontal, MCTheme.panelPadding)
        .padding(.vertical, 6)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(agent.conversationHistory.indices, id: \.self) { i in
                        messageBubble(agent.conversationHistory[i], index: i)
                    }
                }
                .padding(MCTheme.panelPadding)
            }
            .onChange(of: agent.conversationHistory.count) { _, _ in
                if let last = agent.conversationHistory.indices.last {
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
        }
    }

    private func messageBubble(_ message: ChatMessage, index: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Circle()
                .fill(message.role == .user ? MCTheme.statusBlue : MCTheme.statusGray)
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

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask \(agent.role.displayName) agent...", text: $inputText)
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

    private var statusColor: Color {
        switch agent.status {
        case .idle:      return MCTheme.statusGreen
        case .thinking:  return MCTheme.statusBlue
        case .executing: return MCTheme.statusBlue
        case .error:     return MCTheme.statusRed
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        isLoading = true

        Task {
            do {
                let snapshot = state.engineAPI.takeSnapshot()
                let response = try await agent.chat(
                    message: text,
                    snapshot: snapshot,
                    settings: state.aiSettings
                )

                if !response.toolCalls.isEmpty {
                    var results: [ToolResult] = []
                    for call in response.toolCalls {
                        let result = try await state.engineAPI.executeTool(
                            name: call.tool,
                            arguments: call.arguments
                        )
                        results.append(result)
                    }

                    let updatedSnapshot = state.engineAPI.takeSnapshot()
                    let _ = try await agent.handleToolResults(
                        results,
                        snapshot: updatedSnapshot,
                        settings: state.aiSettings
                    )
                }

                await MainActor.run { isLoading = false }
            } catch {
                await MainActor.run {
                    agent.conversationHistory.append(
                        ChatMessage(role: .assistant, content: "Error: \(error.localizedDescription)")
                    )
                    isLoading = false
                }
            }
        }
    }
}
