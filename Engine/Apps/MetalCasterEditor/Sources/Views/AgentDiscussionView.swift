import SwiftUI
import MetalCasterAI

/// Main panel content for the Agent / Colab area.
/// Tab selection is driven by the panel title bar, not an internal tab bar.
struct AgentDiscussionView: View {
    @Environment(EditorState.self) private var state
    @Binding var selectedTab: Int
    @State private var selectedAgent: AgentRole?

    var body: some View {
        Group {
            if selectedTab == 0 {
                agentTab
            } else {
                ColabChatView()
            }
        }
        .background(MCTheme.background)
    }

    @ViewBuilder
    private var agentTab: some View {
        if let role = selectedAgent,
           let agent = state.agentRegistry.agent(for: role) {
            AgentChatView(agent: agent) {
                selectedAgent = nil
            }
        } else {
            AgentListView(selectedAgent: $selectedAgent)
        }
    }
}
