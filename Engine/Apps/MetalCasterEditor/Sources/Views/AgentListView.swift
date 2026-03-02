import SwiftUI
import MetalCasterAI

/// Displays all registered agents with status indicators. Selecting one opens its chat.
struct AgentListView: View {
    @Environment(EditorState.self) private var state
    @Binding var selectedAgent: AgentRole?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(state.agentRegistry.allAgents, id: \.id) { agent in
                    agentRow(agent)
                }
            }
            .padding(.horizontal, MCTheme.panelPadding)
            .padding(.vertical, 8)
        }
    }

    private func agentRow(_ agent: MCAgent) -> some View {
        Button {
            selectedAgent = agent.role
        } label: {
            HStack(spacing: 8) {
                MCStatusDot(color: statusColor(for: agent.status))

                Image(systemName: agent.role.icon)
                    .font(MCTheme.fontCaption)
                    .foregroundStyle(MCTheme.textSecondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 1) {
                    Text(agent.role.displayName)
                        .font(MCTheme.fontBody)
                        .foregroundStyle(MCTheme.textPrimary)
                    Text(agent.role.tagline)
                        .font(MCTheme.fontSmall)
                        .foregroundStyle(MCTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text(agent.status.rawValue)
                    .font(MCTheme.fontSmall)
                    .foregroundStyle(MCTheme.textTertiary)
            }
            .frame(minHeight: MCTheme.rowHeight + 8)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusColor(for status: AgentStatus) -> Color {
        switch status {
        case .idle:      return MCTheme.statusGreen
        case .thinking:  return MCTheme.statusBlue
        case .executing: return MCTheme.statusBlue
        case .error:     return MCTheme.statusRed
        }
    }
}
