import SwiftUI

struct SceneComposerProAIChat: View {
    @Binding var messages: [ComposerChatMessage]
    @Binding var inputText: String
    @Binding var currentPlan: CompositionPlan?
    var onSend: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().background(MCTheme.panelBorder)
            messageList
            Divider().background(MCTheme.panelBorder)

            if let plan = currentPlan {
                planPreview(plan)
                Divider().background(MCTheme.panelBorder)
            }

            inputBar
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("AI")
                .font(MCTheme.fontPanelLabel)
                .foregroundStyle(MCTheme.textSecondary)
            Text("Composer")
                .font(MCTheme.fontPanelLabelBold)
                .foregroundStyle(MCTheme.textPrimary)
            Spacer()
            MCStatusDot(color: .green)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(messages) { message in
                        messageBubble(message)
                            .id(message.id)
                    }
                }
                .padding(10)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func messageBubble(_ message: ComposerChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(MCTheme.fontBody)
                    .foregroundStyle(MCTheme.textPrimary)
                    .textSelection(.enabled)

                Text(message.timestamp, style: .time)
                    .font(.system(size: 9))
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(message.isUser ? Color.white.opacity(0.06) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if !message.isUser {
                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Plan Preview

    private func planPreview(_ plan: CompositionPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 10))
                Text(plan.title)
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text(plan.status.rawValue)
                    .font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(planStatusColor(plan.status).opacity(0.2))
                    .clipShape(Capsule())
            }
            .foregroundStyle(MCTheme.textPrimary)

            ForEach(plan.stages) { stage in
                HStack(spacing: 6) {
                    Image(systemName: stageIcon(stage.status))
                        .font(.system(size: 9))
                        .foregroundStyle(stageStatusColor(stage.status))
                    Text("\(stage.order). \(stage.name)")
                        .font(MCTheme.fontCaption)
                        .foregroundStyle(MCTheme.textSecondary)
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.03))
    }

    private func planStatusColor(_ status: CompositionPlan.PlanStatus) -> Color {
        switch status {
        case .draft:     return .gray
        case .confirmed: return .blue
        case .executing: return .orange
        case .completed: return .green
        case .failed:    return .red
        }
    }

    private func stageIcon(_ status: CompositionPlan.PlanStage.StageStatus) -> String {
        switch status {
        case .pending:   return "circle"
        case .running:   return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        }
    }

    private func stageStatusColor(_ status: CompositionPlan.PlanStage.StageStatus) -> Color {
        switch status {
        case .pending:   return MCTheme.textTertiary
        case .running:   return .orange
        case .completed: return .green
        case .failed:    return .red
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Describe your scene...", text: $inputText)
                .textFieldStyle(.plain)
                .font(MCTheme.fontBody)
                .mcInputStyle()
                .onSubmit { onSend() }

            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(inputText.isEmpty ? MCTheme.textTertiary : MCTheme.textPrimary)
            }
            .buttonStyle(.plain)
            .disabled(inputText.isEmpty)
        }
        .padding(10)
    }
}

// MARK: - Chat Message

struct ComposerChatMessage: Identifiable, Equatable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date

    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
}
